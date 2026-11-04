import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/domain/models/distill.dart';
import 'package:coread/features/distill/distill_controller.dart';
import 'package:coread/features/distill/distill_page.dart';

DistillJob _job({
  DistillStatus status = DistillStatus.running,
  int done = 12,
  int total = 47,
  String? error,
}) =>
    DistillJob(
      id: 'job-1',
      bookId: 'book-1',
      contentHash: 'h',
      status: status,
      stage: DistillStage.map,
      pipelineVersion: 1,
      totalUnits: total,
      doneUnits: done,
      errorText: error,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders unit progress and the stage label', (tester) async {
    await tester.pumpWidget(_host(DistillView(
      state: DistillState(job: _job(), isRunning: true),
      artifacts: const [],
    )));

    expect(find.text('12 / 47'), findsOneWidget);
    expect(find.textContaining('逐段提炼'), findsWidgets);
  });

  testWidgets('pause button stops a running job', (tester) async {
    var paused = 0;
    await tester.pumpWidget(_host(DistillView(
      state: DistillState(job: _job(), isRunning: true),
      artifacts: const [],
      onPause: () => paused++,
    )));

    expect(find.text('暂停'), findsOneWidget);
    await tester.tap(find.text('暂停'));
    expect(paused, 1);
  });

  testWidgets('a paused job offers resume', (tester) async {
    var resumed = 0;
    await tester.pumpWidget(_host(DistillView(
      state: DistillState(
        job: _job(status: DistillStatus.paused, error: 'seg-0003: 超时'),
      ),
      artifacts: const [],
      onResume: () => resumed++,
    )));

    expect(find.textContaining('seg-0003'), findsOneWidget);
    await tester.tap(find.text('继续'));
    expect(resumed, 1);
  });

  testWidgets('a changed book shows a stale notice', (tester) async {
    await tester.pumpWidget(_host(DistillView(
      state: DistillState(
        job: _job(status: DistillStatus.paused),
        notice: '书籍内容已变化，已按新内容重新蒸馏',
      ),
      artifacts: const [],
    )));

    expect(find.textContaining('书籍内容已变化'), findsOneWidget);
  });

  testWidgets('a completed job shows the four artifact tabs', (tester) async {
    await tester.pumpWidget(_host(DistillView(
      state: DistillState(
        job: _job(status: DistillStatus.completed, done: 47, total: 47),
      ),
      artifacts: [
        DistillArtifact(
          id: 'a1',
          bookId: 'book-1',
          kind: DistillArtifactKind.overview,
          unitKey: 'overview',
          title: '全书总览',
          body: '福贵的一生就是活着本身。',
          dataJson: '{"oneLiner":"一个人一生的苦难"}',
          stale: false,
          createdAt: DateTime(2026),
        ),
        DistillArtifact(
          id: 'a2',
          bookId: 'book-1',
          kind: DistillArtifactKind.chapterGist,
          unitKey: 'gist-0000',
          title: '第一章',
          body: '福贵输光了家产。',
          dataJson: '{"gist":"福贵输光了家产。"}',
          chapterStart: 0,
          chapterEnd: 0,
          stale: false,
          createdAt: DateTime(2026),
        ),
      ],
    )));

    expect(find.text('总览'), findsOneWidget);
    expect(find.text('章节地图'), findsOneWidget);
    expect(find.text('卡片'), findsOneWidget);
    expect(find.text('语气'), findsOneWidget);
    expect(find.textContaining('活着本身'), findsOneWidget);

    await tester.tap(find.text('章节地图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('输光了家产'), findsOneWidget);
  });
}
