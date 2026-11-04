import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/features/companion/companion_clip.dart';

Widget _host(Widget child) => MaterialApp(
  home: Center(child: SizedBox(width: 150, height: 200, child: child)),
);

void main() {
  group('CompanionClipStage', () {
    testWidgets('starts on the idle loop and paints nothing before the sheet '
        'arrives', (tester) async {
      await tester.pumpWidget(
        _host(const CompanionClipStage(animate: false)),
      );

      final state = tester.state<CompanionClipStageState>(
        find.byType(CompanionClipStage),
      );
      expect(state.clip, companionIdleClip);
      expect(state.frame, 0);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('holds one frame when animation is off', (tester) async {
      await tester.pumpWidget(
        _host(const CompanionClipStage(animate: false)),
      );
      await tester.pump(const Duration(seconds: 1));

      final state = tester.state<CompanionClipStageState>(
        find.byType(CompanionClipStage),
      );
      expect(state.frame, 0);
    });

    testWidgets('advances frames while animating', (tester) async {
      await tester.pumpWidget(_host(const CompanionClipStage()));
      await tester.pump(const Duration(milliseconds: 260));

      final state = tester.state<CompanionClipStageState>(
        find.byType(CompanionClipStage),
      );
      expect(state.frame, greaterThan(0));
      expect(state.frame, lessThan(companionIdleClip.frameCount));
    });

    testWidgets('plays a one-shot clip and goes back to idle', (tester) async {
      await tester.pumpWidget(_host(const CompanionClipStage()));

      final state = tester.state<CompanionClipStageState>(
        find.byType(CompanionClipStage),
      );
      state.play(companionPokeClip);
      await tester.pump();
      expect(state.clip, companionPokeClip);
      expect(state.frame, 0);

      // The clip is 48 frames at 12 fps: four seconds and a bit.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.clip, companionIdleClip);
    });
  });
}
