import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_avatar.dart';
import 'package:hackathon_reading/features/companion/companion_clip.dart';
import 'package:hackathon_reading/features/companion/companion_skin.dart';

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

  testWidgets('pressing the character plays the poke clip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CompanionAvatar(height: 160))),
      ),
    );
    await tester.pumpAndSettle();

    final stage = tester.state<CompanionClipStageState>(
      find.byType(CompanionClipStage),
    );
    expect(stage.clip, companionIdleClip);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('companion-avatar'))),
    );
    await tester.pump();
    expect(stage.clip, companionPokeClip);
    await gesture.up();
  });

  testWidgets('dragging the character plays the drag clip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CompanionAvatar(height: 160))),
      ),
    );
    await tester.pumpAndSettle();

    final stage = tester.state<CompanionClipStageState>(
      find.byType(CompanionClipStage),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('companion-avatar'))),
    );
    // A drag only wins the arena past the slop distance.
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    expect(stage.clip, companionDragClip);

    await gesture.up();
    await tester.pump();
    expect(stage.clip, companionIdleClip);
  });

  testWidgets('draws the skin it is given and keeps reacting', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CompanionAvatar(
              height: 160,
              skin: companionWriterSkin,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stage = tester.state<CompanionClipStageState>(
      find.byType(CompanionClipStage),
    );
    expect(stage.clip, companionWriterIdleClip);

    // The imported art has a single motion, so a poke keeps the idle loop but
    // the tap must still reach the host.
    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    expect(stage.clip, companionWriterIdleClip);
    expect(taps, 1);
  });

  testWidgets('swaps the loop when the skin changes in place', (tester) async {
    Widget host(CompanionSkin skin) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: CompanionAvatar(height: 160, skin: skin),
            ),
          ),
        );

    await tester.pumpWidget(host(companionDonutSkin));
    await tester.pumpAndSettle();
    final stage = tester.state<CompanionClipStageState>(
      find.byType(CompanionClipStage),
    );
    expect(stage.clip, companionIdleClip);

    await tester.pumpWidget(host(companionWriterSkin));
    await tester.pumpAndSettle();
    expect(stage.clip, companionWriterIdleClip);
  });
}
