import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_avatar.dart';

void main() {
  testWidgets('draws a 3:4 placeholder when no asset is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CompanionAvatar(height: 160))),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('companion-avatar')));
    expect(rect.height, 160);
    expect(rect.width, 120);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('honours the height it is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CompanionAvatar(height: 120))),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('companion-avatar')));
    expect(rect.height, 120);
    expect(rect.width, 90);
  });

  testWidgets('falls back to the painter when the asset is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CompanionAvatar(height: 120, assetPath: 'assets/nope.png'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A missing asset must not throw; the painter keeps the character visible.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('companion-avatar')), findsOneWidget);
  });
}
