import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/features/reader/illustration_source.dart';
import 'package:coread/features/reader/illustration_source_sheet.dart';

void main() {
  testWidgets('the sheet offers the page, nearby pages and the chapter',
      (tester) async {
    IllustrationSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showIllustrationSourceSheet(context);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('illustration-source-sheet')), findsOneWidget);
    expect(find.text('从哪里取文生图？'), findsOneWidget);
    expect(find.text('当前页'), findsOneWidget);
    expect(find.text('前后页面'), findsOneWidget);
    expect(find.text('整章'), findsOneWidget);

    await tester.tap(find.byKey(const Key('illustration-source-nearby')));
    await tester.pumpAndSettle();

    expect(picked, IllustrationSource.nearby);
    expect(find.byKey(const Key('illustration-source-sheet')), findsNothing);
  });

  testWidgets('the chapter choice is returned too', (tester) async {
    IllustrationSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showIllustrationSourceSheet(context);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('illustration-source-chapter')));
    await tester.pumpAndSettle();

    expect(picked, IllustrationSource.chapter);
  });
}
