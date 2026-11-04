import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_presence.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('greets with a popping bubble then hides itself', (tester) async {
    await tester.pumpWidget(_host(const CompanionPresence(height: 160)));
    expect(find.byKey(const Key('companion-bubble')), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 40));

    // Mid pop: the bubble is mounted and partway through its scale animation.
    expect(find.byKey(const Key('companion-bubble')), findsOneWidget);
    final midScale = tester
        .widget<ScaleTransition>(find.byKey(const Key('companion-bubble-scale')))
        .scale
        .value;
    expect(midScale, greaterThan(0.0));

    await tester.pumpAndSettle();
    expect(find.text('读到哪儿了？'), findsOneWidget);
    final settledScale = tester
        .widget<ScaleTransition>(find.byKey(const Key('companion-bubble-scale')))
        .scale
        .value;
    expect(settledScale, closeTo(1.0, 0.001));

    // Six seconds later it retracts on its own.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('does not greet on its own when autoGreet is off', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionPresence(height: 160, autoGreet: false)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('tapping the avatar opens and closes the bubble', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionPresence(height: 160, autoGreet: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('tapping the bubble closes it', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionPresence(height: 160, autoGreet: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-bubble')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('sits above the avatar, right-aligned', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionPresence(height: 160, autoGreet: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    final bubble = tester.getRect(find.byKey(const Key('companion-bubble')));
    final avatar = tester.getRect(find.byKey(const Key('companion-avatar')));
    expect(bubble.bottom, lessThanOrEqualTo(avatar.top + 1));
    expect(bubble.right, closeTo(avatar.right, 1));
  });
}
