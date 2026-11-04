import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/reader/illustration_viewer.dart';

void main() {
  Future<void> open(WidgetTester tester, String path) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => openIllustrationViewer(context, path),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens full screen and closes with the button', (tester) async {
    await open(tester, 'C:/missing/illustration.png');
    expect(find.byKey(const Key('illustration-viewer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('illustration-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('illustration-viewer')), findsNothing);
  });

  testWidgets('closes with Escape and with a blank tap', (tester) async {
    await open(tester, 'C:/missing/illustration.png');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('illustration-viewer')), findsNothing);

    await open(tester, 'C:/missing/illustration.png');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('illustration-viewer')), findsNothing);
  });

  testWidgets('shows an error when the file cannot be loaded', (tester) async {
    await open(tester, 'C:/missing/other.png');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('无法加载插图'), findsOneWidget);
  });
}
