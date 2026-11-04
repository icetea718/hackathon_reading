import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/distill_artifact_repository.dart';
import 'package:hackathon_reading/data/repositories/distill_job_repository.dart';
import 'package:hackathon_reading/data/repositories/distill_unit_repository.dart';
import 'package:hackathon_reading/distill/distill_pipeline.dart';
import 'package:hackathon_reading/distill/distill_planner.dart';
import 'package:hackathon_reading/distill/llm/llm_client.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/domain/models/distill.dart';

class _ScriptedClient implements LlmClient {
  _ScriptedClient({this.onCall});

  final void Function(int call, CancelToken? token)? onCall;
  final List<String> prompts = [];
  int calls = 0;

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) =>
      Stream.value(complete(messages));

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async {
    calls += 1;
    prompts.add(messages.last.content);
    onCall?.call(calls, cancel);
    return complete(messages);
  }

  String complete(List<LlmMessage> messages) {
    final prompt = messages.last.content;
    if (prompt.contains('请提炼这一片段')) {
      return '{"points": ["福贵输光家产"], "entities": ["福贵"], '
          '"toneCues": ["自嘲"], "quotes": ["我年轻的时候真是个败家子"]}';
    }
    if (prompt.contains('压缩梗概')) {
      return '{"summary": "这一组讲福贵败家与被抓壮丁", "chapters": ['
          '{"chapterIndex": 0, "title": "第一章", "gist": "输光家产"},'
          '{"chapterIndex": 1, "title": "第二章", "gist": "被抓壮丁"},'
          '{"chapterIndex": 2, "title": "第三章", "gist": "回家"}]}';
    }
    if (prompt.contains('全书总览')) {
      return '{"oneLiner": "一个人一生的苦难", "synopsis": "福贵的一生", '
          '"themes": ["活着"], "structure": [], "argument": "活着本身"}';
    }
    if (prompt.contains('语气与情感走向')) {
      return '{"overall": "克制的悲悯", "narrator": "老年福贵", "arc": [], '
          '"style": ["白描"], "sampleQuotes": ["我年轻的时候真是个败家子"]}';
    }
    if (prompt.contains('陪读卡片')) {
      return '[{"slug": "loss", "title": "败家", "type": "case", '
          '"definition": "福贵把家产输光", "sourceChapters": [0], '
          '"quote": "我年轻的时候真是个败家子"}]';
    }
    return '{}';
  }

  @override
  void dispose() {}
}

void main() {
  late AppDatabase db;
  late DistillJobRepository jobs;
  late DistillUnitRepository units;
  late DistillArtifactRepository artifacts;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    jobs = DistillJobRepository(db);
    units = DistillUnitRepository(db);
    artifacts = DistillArtifactRepository(db);
  });
  tearDown(() => db.close());

  Chapter chapter(int index, String text) => Chapter(
        id: 'c$index',
        bookId: 'book-1',
        index: index,
        title: '第${index + 1}章',
        startOffset: 0,
        endOffset: text.length,
        contentText: text,
      );

  List<Chapter> smallBook() => [
        chapter(0, '福贵牵着老牛走在田埂上，他说起自己年轻时的事。\n' * 3),
        chapter(1, '他被抓了壮丁，在战场上活了下来。\n' * 3),
        chapter(2, '他回到家里，家珍还在等他。\n' * 3),
      ];

  DistillPipeline pipeline(
    List<Chapter> chapters,
    LlmClient client, {
    String contentHash = 'hash-1',
    int concurrency = 3,
  }) =>
      DistillPipeline(
        bookId: 'book-1',
        contentHash: contentHash,
        chapters: chapters,
        client: client,
        planner: DistillPlanner(),
        jobs: jobs,
        units: units,
        artifacts: artifacts,
        bookTitle: '活着',
        author: '余华',
        concurrency: concurrency,
      );

  test('a small book produces every artifact kind', () async {
    final client = _ScriptedClient();

    await pipeline(smallBook(), client).run();

    final job = await jobs.getByBook('book-1');
    expect(job!.status, DistillStatus.completed);
    expect(job.doneUnits, job.totalUnits);
    expect(client.calls, lessThanOrEqualTo(80));

    final all = await artifacts.listByBook('book-1');
    expect(all.where((a) => a.kind == DistillArtifactKind.overview), hasLength(1));
    expect(all.where((a) => a.kind == DistillArtifactKind.tone), hasLength(1));
    expect(all.where((a) => a.kind == DistillArtifactKind.chapterGist), hasLength(3));
    expect(all.where((a) => a.kind == DistillArtifactKind.card), isNotEmpty);
  });

  test('resuming only calls the model for missing units', () async {
    final failing = _ScriptedClient(
      onCall: (call, token) {
        if (call >= 2) throw LlmException('network down');
      },
    );
    await pipeline(smallBook(), failing).run();

    expect((await jobs.getByBook('book-1'))!.status, DistillStatus.paused);

    final healthy = _ScriptedClient();
    await pipeline(smallBook(), healthy).run();

    final job = await jobs.getByBook('book-1');
    expect(job!.status, DistillStatus.completed);
    expect(healthy.calls, lessThan(failing.calls + 10));
    expect((await artifacts.listByBook('book-1')).isNotEmpty, isTrue);
  });

  test('cancelling stops issuing new calls', () async {
    final token = CancelToken();
    final client = _ScriptedClient(
      onCall: (call, cancel) {
        if (call == 1) cancel?.cancel();
      },
    );

    await pipeline(smallBook(), client).run(cancel: token);

    final job = await jobs.getByBook('book-1');
    expect(job!.status, DistillStatus.canceled);
    expect(client.calls, 1);
  });

  test('bad json twice pauses the job with an error', () async {
    final client = _ScriptedClient(onCall: (call, token) {});
    final broken = _BadJsonClient();

    await pipeline(smallBook(), broken).run();

    final job = await jobs.getByBook('book-1');
    expect(job!.status, DistillStatus.paused);
    expect(job.errorText, isNotNull);
    expect(client.calls, 0);
  });

  test('a one-chapter book with a long chapter still completes', () async {
    final client = _ScriptedClient();
    final chapters = [chapter(0, '福贵说起了从前。\n' * 1500)];

    await pipeline(chapters, client).run();

    final job = await jobs.getByBook('book-1');
    expect(job!.status, DistillStatus.completed);
    expect(DistillPlanner().plan(chapters).segments.length, greaterThan(1));
  });
}

class _BadJsonClient extends _ScriptedClient {
  _BadJsonClient();

  @override
  String complete(List<LlmMessage> messages) => '{"points": ["未闭合"';
}
