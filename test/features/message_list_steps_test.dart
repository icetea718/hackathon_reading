import 'package:coread/data/db/app_database.dart';
import 'package:coread/features/search/message_list.dart';
import 'package:coread/features/search/steps_bar.dart';
import 'package:coread/search/search_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessageRow _row({String? stepsJson, String status = 'complete'}) =>
    ChatMessageRow(
      id: 'm1',
      threadId: 't1',
      role: 'assistant',
      content: '答案',
      stepsJson: stepsJson,
      status: status,
      createdAt: DateTime.utc(2026, 11, 5),
    );

Widget _host(List<ChatMessageRow> rows, {bool streaming = false}) =>
    MaterialApp(
      home: Scaffold(
        body: MessageList(
          messages: rows,
          streaming: streaming,
          searching: false,
          hits: const [],
          degraded: false,
        ),
      ),
    );

void main() {
  testWidgets('带 stepsJson 的助手行在正文上方渲染步骤条', (tester) async {
    final steps = [
      const SearchStep(
        tool: 'search_in_book',
        summary: '检索「雨」',
        chapters: [7],
        hits: 1,
        ms: 90,
      ),
    ];

    await tester.pumpWidget(
      _host([_row(stepsJson: SearchStep.listToJson(steps))]),
    );

    expect(find.byType(StepsBar), findsOneWidget);
    expect(find.textContaining('检索 1 次'), findsOneWidget);
    expect(find.text('答案'), findsOneWidget);
  });

  testWidgets('只有步骤还没有正文时也渲染这一行', (tester) async {
    final steps = [
      const SearchStep(
        tool: 'get_chapter',
        summary: '读第 3 章',
        chapters: [3],
        hits: 0,
        ms: 40,
      ),
    ];
    final row = ChatMessageRow(
      id: 'm2',
      threadId: 't1',
      role: 'assistant',
      content: '',
      stepsJson: SearchStep.listToJson(steps),
      status: 'streaming',
      createdAt: DateTime.utc(2026, 11, 5),
    );

    await tester.pumpWidget(_host([row], streaming: true));

    expect(find.byType(StepsBar), findsOneWidget);
    expect(find.textContaining('读第 3 章'), findsOneWidget);
  });

  testWidgets('没有步骤的旧消息不渲染步骤条', (tester) async {
    await tester.pumpWidget(_host([_row()]));

    expect(find.byType(StepsBar), findsNothing);
    expect(find.text('答案'), findsOneWidget);
  });
}
