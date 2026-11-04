import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coread/features/search/markdown_message.dart';

Future<void> pumpMessage(WidgetTester tester, String data) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: MarkdownMessage(data: data))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders a heading and the paragraph under it', (tester) async {
    await pumpMessage(tester, '# 第一章\n\n正文在这里。');

    expect(find.textContaining('第一章', findRichText: true), findsOneWidget);
    expect(find.textContaining('正文在这里。', findRichText: true), findsOneWidget);
    // The hash itself is syntax, not text.
    expect(find.textContaining('# 第一章', findRichText: true), findsNothing);
  });

  testWidgets('renders list items and code blocks', (tester) async {
    await pumpMessage(
      tester,
      '- 第一条\n- 第二条\n\n```dart\nfinal a = 1;\n```',
    );

    expect(find.textContaining('第一条', findRichText: true), findsOneWidget);
    expect(find.textContaining('第二条', findRichText: true), findsOneWidget);
    expect(find.textContaining('final a = 1;', findRichText: true), findsOne);
    expect(find.textContaining('```', findRichText: true), findsNothing);
  });

  testWidgets('renders bold and inline code as text, not markers',
      (tester) async {
    await pumpMessage(tester, '这是**加粗**和 `代码` 的混排。');

    final rendered = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    expect(rendered, contains('加粗'));
    expect(rendered, contains('代码'));
    expect(rendered, isNot(contains('**')));
    expect(rendered, isNot(contains('`')));
  });

  testWidgets('reply with unclosed markers still renders', (tester) async {
    await pumpMessage(tester, '流式输出到一半：**还没结束');

    expect(
      find.textContaining('流式输出到一半', findRichText: true),
      findsOneWidget,
    );
  });
}
