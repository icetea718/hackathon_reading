import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_avatar.dart';
import 'package:hackathon_reading/features/companion/companion_idle_sprite.dart';

void main() {
  testWidgets('advances through the baked idle frames', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 160,
              child: CompanionIdleSprite(),
            ),
          ),
        ),
      ),
    );

    // First pump starts the ticker and loads the sheet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final state = tester.state<CompanionIdleSpriteState>(
      find.byType(CompanionIdleSprite),
    );
    final start = state.frameIndex;

    await tester.pump(const Duration(milliseconds: 300));
    expect(state.frameIndex, isNot(start));
    expect(state.frameIndex, lessThan(companionIdleFrameCount));

    // Wind the ticker down so the test ends with no live animation.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('holds the first frame when animation is off', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 160,
              child: CompanionIdleSprite(animate: false),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final state = tester.state<CompanionIdleSpriteState>(
      find.byType(CompanionIdleSprite),
    );
    expect(state.frameIndex, 0);
  });

  testWidgets('the bundled sprite is drawn from the baked sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CompanionAvatar(height: 160, assetPath: companionSprite),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CompanionIdleSprite), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
