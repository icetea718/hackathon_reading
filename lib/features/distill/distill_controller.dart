import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/distill.dart';
import '../../distill/distill_pipeline.dart';
import '../../distill/distill_planner.dart';
import '../../distill/llm/llm_client.dart';
import '../../distill/stale_guard.dart';

/// UI-facing state of one book's distillation.
class DistillState {
  const DistillState({
    this.job,
    this.progress,
    this.error,
    this.notice,
    this.isRunning = false,
  });

  final DistillJob? job;
  final DistillProgress? progress;
  final String? error;

  /// Non-fatal hint, e.g. that the book changed and was re-distilled.
  final String? notice;
  final bool isRunning;

  DistillState copyWith({
    DistillJob? job,
    DistillProgress? progress,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
    bool? isRunning,
  }) {
    return DistillState(
      job: job ?? this.job,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

/// Owns the pipeline run for a single book and keeps it alive across pages.
class DistillController extends Notifier<DistillState> {
  DistillController(this.bookId);

  final String bookId;

  CancelToken? _cancel;
  bool _pauseRequested = false;

  @override
  DistillState build() {
    ref.keepAlive();
    Future<void>.microtask(_reload);
    return const DistillState();
  }

  Future<void> start() => _run();

  Future<void> resume() => _run();

  /// Asks the running loop to stop after the unit in flight; the job is then
  /// left `paused` so it can be resumed.
  void pause() {
    if (!state.isRunning) return;
    _pauseRequested = true;
  }

  void cancel() {
    _pauseRequested = false;
    _cancel?.cancel();
  }

  Future<void> _reload() async {
    final job = await ref.read(distillJobRepositoryProvider).getByBook(bookId);
    state = DistillState(
      job: job,
      progress: job == null
          ? null
          : DistillProgress(
              stage: job.stage,
              doneUnits: job.doneUnits,
              totalUnits: job.totalUnits,
            ),
      error: state.error,
      notice: state.notice,
      isRunning: state.isRunning,
    );
  }

  Future<void> _run() async {
    if (state.isRunning) return;

    final config = await ref.read(llmConfigStoreProvider).load();
    if (!config.isConfigured) {
      state = state.copyWith(error: '未配置 AI 服务，请到设置页填写');
      return;
    }

    final book = await ref.read(bookRepositoryProvider).getById(bookId);
    if (book == null) {
      state = state.copyWith(error: '书籍不存在');
      return;
    }
    final chapters = await ref.read(chapterRepositoryProvider).getForBook(bookId);
    if (chapters.isEmpty) {
      state = state.copyWith(error: '这本书没有可蒸馏的章节');
      return;
    }

    final check = await DistillStaleGuard(
      books: ref.read(bookRepositoryProvider),
      artifacts: ref.read(distillArtifactRepositoryProvider),
    ).ensureFresh(book);

    final token = CancelToken();
    _cancel = token;
    _pauseRequested = false;
    state = state.copyWith(
      isRunning: true,
      clearError: true,
      notice: check.changed ? '书籍内容已变化，已按新内容重新蒸馏' : null,
      clearNotice: !check.changed,
    );

    final pipeline = DistillPipeline(
      bookId: bookId,
      contentHash: check.hash ?? book.contentHash ?? '',
      chapters: chapters,
      client: ref.read(llmClientProvider),
      planner: DistillPlanner(),
      jobs: ref.read(distillJobRepositoryProvider),
      units: ref.read(distillUnitRepositoryProvider),
      artifacts: ref.read(distillArtifactRepositoryProvider),
      bookTitle: book.title,
      author: book.author,
    );

    try {
      await pipeline.run(
        cancel: token,
        onProgress: (progress) {
          if (_pauseRequested && !token.isCanceled) token.cancel();
          state = state.copyWith(progress: progress);
        },
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    } finally {
      _cancel = null;
      final wasPaused = _pauseRequested;
      _pauseRequested = false;
      final repository = ref.read(distillJobRepositoryProvider);
      var job = await repository.getByBook(bookId);
      if (wasPaused && job != null && job.status == DistillStatus.canceled) {
        job = job.copyWith(status: DistillStatus.paused);
        await repository.save(job);
      }
      state = DistillState(
        job: job,
        progress: state.progress,
        error: job?.errorText ?? state.error,
        notice: state.notice,
        isRunning: false,
      );
      if (job?.status == DistillStatus.completed) {
        ref.invalidate(distillArtifactsProvider(bookId));
      }
    }
  }
}

final distillControllerProvider =
    NotifierProvider.family<DistillController, DistillState, String>(
  DistillController.new,
);
