import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/repositories/distill_artifact_repository.dart';
import '../data/repositories/distill_job_repository.dart';
import '../data/repositories/distill_unit_repository.dart';
import '../domain/models/chapter.dart';
import '../domain/models/distill.dart';
import 'distill_models.dart';
import 'distill_planner.dart';
import 'distill_prompts.dart';
import 'llm/llm_client.dart';
import 'quote_verifier.dart';

class DistillProgress {
  const DistillProgress({
    required this.stage,
    required this.doneUnits,
    required this.totalUnits,
    this.currentUnit,
  });

  final DistillStage stage;
  final int doneUnits;
  final int totalUnits;
  final String? currentUnit;
}

class _Canceled implements Exception {
  const _Canceled();
}

/// Runs the distill stages against an [LlmClient], persisting every unit so a
/// later run can resume where this one stopped.
class DistillPipeline {
  DistillPipeline({
    required this.bookId,
    required this.contentHash,
    required this.chapters,
    required this.client,
    required this.planner,
    required this.jobs,
    required this.units,
    required this.artifacts,
    this.bookTitle = '',
    this.author = '',
    this.pipelineVersion = 1,
    this.concurrency = 3,
    String Function()? newId,
    DateTime Function()? clock,
  })  : _newId = newId ?? const Uuid().v4,
        _clock = clock ?? DateTime.now;

  final String bookId;
  final String contentHash;
  final List<Chapter> chapters;
  final LlmClient client;
  final DistillPlanner planner;
  final DistillJobRepository jobs;
  final DistillUnitRepository units;
  final DistillArtifactRepository artifacts;
  final String bookTitle;
  final String author;
  final int pipelineVersion;
  final int concurrency;
  final String Function() _newId;
  final DateTime Function() _clock;

  Future<void> run({
    void Function(DistillProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    final job = await _ensureJob();
    if (job.status == DistillStatus.completed) {
      onProgress?.call(
        DistillProgress(
          stage: DistillStage.verify,
          doneUnits: job.doneUnits,
          totalUnits: job.totalUnits,
        ),
      );
      return;
    }

    final plan = planner.plan(chapters);
    final totalUnits = plan.segments.length + plan.parts.length + 3;
    var current = job.copyWith(
      status: DistillStatus.running,
      stage: DistillStage.map,
      totalUnits: totalUnits,
      errorText: null,
      updatedAt: _clock(),
    );
    await jobs.save(current);

    final done = await units.doneKeys(current.id);
    final stored = {
      for (final unit in await units.listByJob(current.id))
        if (unit.resultJson != null) unit.unitKey: unit.resultJson!,
    };
    var doneUnits = job.doneUnits;

    void emit(String key) {
      onProgress?.call(
        DistillProgress(
          stage: current.stage,
          doneUnits: doneUnits,
          totalUnits: totalUnits,
          currentUnit: key,
        ),
      );
    }

    Future<String> runUnit(
      String key,
      String kind,
      List<LlmMessage> messages, {
      required bool parseCheck,
    }) async {
      final existing = stored[key];
      if (done.contains(key) && existing != null) return existing;
      if (cancel?.isCanceled ?? false) throw const _Canceled();

      var attempt = 0;
      while (true) {
        attempt++;
        try {
          final raw = await client.completeJson(messages, cancel: cancel);
          if (parseCheck) _validate(raw, key);
          await units.put(
            DistillUnit(
              id: '${current.id}#$key',
              jobId: current.id,
              unitKey: key,
              kind: kind,
              status: 'done',
              resultJson: raw,
              attempts: attempt,
              updatedAt: _clock(),
            ),
          );
          done.add(key);
          stored[key] = raw;
          doneUnits += 1;
          current = current.copyWith(doneUnits: doneUnits, updatedAt: _clock());
          await jobs.save(current);
          emit(key);
          return raw;
        } on _Canceled {
          rethrow;
        } catch (error) {
          if (cancel?.isCanceled ?? false) throw const _Canceled();
          if (attempt >= 2) {
            await units.put(
              DistillUnit(
                id: '${current.id}#$key',
                jobId: current.id,
                unitKey: key,
                kind: kind,
                status: 'failed',
                attempts: attempt,
                updatedAt: _clock(),
              ),
            );
            current = current.copyWith(
              status: DistillStatus.paused,
              errorText: '$key: $error',
              doneUnits: doneUnits,
              updatedAt: _clock(),
            );
            await jobs.save(current);
            rethrow;
          }
          messages = [
            ...messages,
            const LlmMessage(
              LlmRole.user,
              '上一次回复不是可用的 JSON。请只输出符合要求的 JSON，不要任何解释或代码围栏。',
            ),
          ];
        }
      }
    }

    final bookText = chapters.map((c) => c.contentText).join('\n');
    final verifier = QuoteVerifier(bookText);


    try {
      // Stage map.
      current = current.copyWith(stage: DistillStage.map);
      await jobs.save(current);
      final mapResults = <String, MapResult>{};
      final queue = plan.segments.toList();
      final workers = <Future<void>>[];
      final lock = _Lock();
      for (var i = 0; i < concurrency; i++) {
        workers.add(() async {
          while (true) {
            final index = await lock.next(queue.length);
            if (index >= queue.length) return;
            final segment = queue[index];
            final raw = await runUnit(
              segment.key,
              'segment',
              mapPrompt(
                segment,
                bookTitle: bookTitle,
                previousGist: index == 0 ? null : mapResults[queue[index - 1].key]?.points.first,
              ),
              parseCheck: true,
            );
            mapResults[segment.key] = parseMapResult(raw);
          }
        }());
      }
      await Future.wait(workers);

      // Stage reduce-1: one compressed summary per part.
      current = current.copyWith(stage: DistillStage.reduce1);
      await jobs.save(current);
      final partResults = <DistillPart, PartResult>{};
      for (final part in plan.parts) {
        final raw = await runUnit(
          part.key,
          'part',
          reducePartPrompt(part, bookTitle: bookTitle),
          parseCheck: true,
        );
        partResults[part] = parsePartResult(raw);
      }

      // Stage reduce-2: overview and tone.
      current = current.copyWith(stage: DistillStage.reduce2);
      await jobs.save(current);
      final partSummaries = [for (final part in plan.parts) partResults[part]!.summary];
      final overviewRaw = await runUnit(
        'overview',
        'overview',
        overviewPrompt(partSummaries, bookTitle: bookTitle, author: author),
        parseCheck: true,
      );
      final overview = parseOverview(overviewRaw);
      await artifacts.put(
        DistillArtifact(
          id: _newId(),
          bookId: bookId,
          kind: DistillArtifactKind.overview,
          unitKey: 'overview',
          title: '全书总览',
          body: overview.synopsis,
          dataJson: overviewRaw,
          stale: false,
          createdAt: _clock(),
        ),
      );

      final toneRaw = await runUnit(
        'tone',
        'tone',
        tonePrompt(partSummaries, bookTitle: bookTitle),
        parseCheck: true,
      );
      final tone = parseTone(toneRaw);
      await artifacts.put(
        DistillArtifact(
          id: _newId(),
          bookId: bookId,
          kind: DistillArtifactKind.tone,
          unitKey: 'tone',
          title: '语气画像',
          body: tone.overall,
          dataJson: toneRaw,
          stale: false,
          createdAt: _clock(),
        ),
      );

      // Chapter gists from the part results.
      for (final part in plan.parts) {
        for (final gist in partResults[part]!.chapters) {
          await artifacts.put(
            DistillArtifact(
              id: _newId(),
              bookId: bookId,
              kind: DistillArtifactKind.chapterGist,
              unitKey: 'gist-${gist.chapterIndex.toString().padLeft(4, '0')}',
              title: gist.title.isEmpty ? '第 ${gist.chapterIndex + 1} 章' : gist.title,
              body: gist.gist,
              dataJson: jsonEncode({'gist': gist.gist, 'summary': partResults[part]!.summary}),
              chapterStart: gist.chapterIndex,
              chapterEnd: gist.chapterIndex,
              stale: false,
              createdAt: _clock(),
            ),
          );
        }
      }

      // Stage cards: candidates come from the map points and quotes.
      current = current.copyWith(stage: DistillStage.cards);
      await jobs.save(current);
      final candidates = [
        for (final entry in mapResults.entries)
          '${entry.key}（第 ${_chapterNumberOf(plan, entry.key) + 1} 章）\n'
              '要点：${entry.value.points.join('；')}\n'
              '原句：${entry.value.quotes.join(' / ')}',
      ];
      final cardsRaw = await runUnit(
        'cards-01',
        'cards',
        cardsPrompt(candidates.take(20).toList(), bookTitle: bookTitle),
        parseCheck: true,
      );
      final cards = parseCards(cardsRaw);
      for (final card in cards) {
        final quoteOk = card.quote != null && verifier.contains(card.quote!);
        final knownChapters = card.sourceChapters
            .where((i) => chapters.any((c) => c.index == i))
            .toList();
        await artifacts.put(
          DistillArtifact(
            id: _newId(),
            bookId: bookId,
            kind: DistillArtifactKind.card,
            unitKey: 'card-${card.slug}',
            title: card.title,
            body: card.definition,
            dataJson: jsonEncode({
              'slug': card.slug,
              'type': card.type,
              'sourceChapters': knownChapters,
              'quote': quoteOk ? card.quote : null,
            }),
            chapterStart: knownChapters.isEmpty ? null : knownChapters.reduce((a, b) => a < b ? a : b),
            chapterEnd: knownChapters.isEmpty ? null : knownChapters.reduce((a, b) => a > b ? a : b),
            stale: false,
            createdAt: _clock(),
          ),
        );
      }

      current = current.copyWith(
        status: DistillStatus.completed,
        stage: DistillStage.verify,
        doneUnits: doneUnits,
        errorText: null,
        updatedAt: _clock(),
      );
      await jobs.save(current);
      emit('done');
    } on _Canceled {
      current = current.copyWith(
        status: DistillStatus.canceled,
        doneUnits: doneUnits,
        updatedAt: _clock(),
      );
      await jobs.save(current);
    } on Exception {
      // runUnit already persisted paused + errorText.
      final reloaded = await jobs.getByBook(bookId);
      if (reloaded != null && reloaded.status != DistillStatus.paused) {
        await jobs.save(
          reloaded.copyWith(
            status: DistillStatus.paused,
            doneUnits: doneUnits,
            updatedAt: _clock(),
          ),
        );
      }
    }
  }

  int _chapterNumberOf(DistillPlan plan, String segmentKey) {
    for (final segment in plan.segments) {
      if (segment.key == segmentKey) return segment.chapterIndex;
    }
    return 0;
  }

  Future<DistillJob> _ensureJob() async {
    final existing = await jobs.getByBook(bookId);
    if (existing != null) {
      final stale = existing.contentHash != contentHash ||
          existing.pipelineVersion != pipelineVersion;
      if (!stale) return existing;
      await artifacts.markStale(bookId);
      await units.deleteForJob(existing.id);
    }
    final job = DistillJob(
      id: _newId(),
      bookId: bookId,
      contentHash: contentHash,
      status: DistillStatus.queued,
      stage: DistillStage.plan,
      pipelineVersion: pipelineVersion,
      totalUnits: 0,
      doneUnits: 0,
      createdAt: _clock(),
      updatedAt: _clock(),
    );
    await jobs.save(job);
    return job;
  }

  void _validate(String raw, String key) {
    if (key.startsWith('seg-')) {
      parseMapResult(raw);
    } else if (key.startsWith('part-')) {
      parsePartResult(raw);
    } else if (key == 'overview') {
      parseOverview(raw);
    } else if (key == 'tone') {
      parseTone(raw);
    } else if (key.startsWith('cards-')) {
      parseCards(raw);
    }
  }
}

/// Tiny round-robin counter used to hand plan items to worker futures.
class _Lock {
  int _next = 0;

  Future<int> next(int limit) async {
    final value = _next;
    _next += 1;
    return value;
  }
}
