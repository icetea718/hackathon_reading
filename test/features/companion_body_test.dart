import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_body.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: SizedBox(width: 120, height: 160, child: child))),
);

void main() {
  testWidgets('squashes when poked and springs back to rest', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionBody(idleMotion: false, child: ColoredBox(color: Colors.blue))),
    );
    final state = tester.state<CompanionBodyState>(find.byType(CompanionBody));

    final centre = tester.getCenter(find.byType(CompanionBody));
    final gesture = await tester.startGesture(centre);
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      state.squash,
      isNot(0),
      reason: 'a press should deform the body right away',
    );
    await gesture.up();

    await tester.pumpAndSettle();
    expect(state.squash, closeTo(0, 0.01));
    expect(state.offset.dx, closeTo(0, 0.5));
    expect(state.offset.dy, closeTo(0, 0.5));
    expect(state.tilt, closeTo(0, 0.01));
  });

  testWidgets('tapping fires the callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        CompanionBody(
          idleMotion: false,
          onTap: () => taps++,
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
    );
    await tester.tap(find.byType(CompanionBody));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('follows a drag and springs home on release', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionBody(idleMotion: false, child: ColoredBox(color: Colors.blue))),
    );
    final state = tester.state<CompanionBodyState>(find.byType(CompanionBody));
    final centre = tester.getCenter(find.byType(CompanionBody));

    final gesture = await tester.startGesture(centre);
    // Real pointers move in many small events; a single jump would only
    // register the drag start.
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(10, -4));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.offset.dx, greaterThan(0));
    expect(state.offset.dy, lessThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.offset.dx, closeTo(0, 0.5));
    expect(state.offset.dy, closeTo(0, 0.5));
  });

  testWidgets('never drags further than its leash allows', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionBody(idleMotion: false, child: ColoredBox(color: Colors.blue))),
    );
    final state = tester.state<CompanionBodyState>(find.byType(CompanionBody));
    final centre = tester.getCenter(find.byType(CompanionBody));

    final gesture = await tester.startGesture(centre);
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(100, 75));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.offset.dx, lessThanOrEqualTo(48.01));
    expect(state.offset.dy, lessThanOrEqualTo(28.01));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('leans towards the pointer while hovered', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionBody(idleMotion: false, child: ColoredBox(color: Colors.blue))),
    );
    final state = tester.state<CompanionBodyState>(find.byType(CompanionBody));
    final rect = tester.getRect(find.byType(CompanionBody));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.center);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(rect.centerRight - const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 120));

    expect(state.tilt.abs(), greaterThan(0.001));

    await mouse.moveTo(const Offset(-100, -100));
    await tester.pumpAndSettle();
    expect(state.tilt.abs(), lessThan(0.01));
  });

  testWidgets('keeps the character upright when idle motion is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const CompanionBody(child: ColoredBox(color: Colors.blue))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final state = tester.state<CompanionBodyState>(find.byType(CompanionBody));
    // Breathing must not drag the body around; it only scales the sprite.
    expect(state.offset.dx.abs(), lessThan(0.5));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
