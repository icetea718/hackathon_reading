import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_clip.dart';
import 'package:hackathon_reading/features/companion/companion_presence.dart';
import 'package:hackathon_reading/features/companion/companion_skin.dart';

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

  testWidgets('says the line its loader picked', (tester) async {
    final loaded = Completer<String?>();
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          greetingLoader: () => loaded.future,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('companion-bubble')), findsNothing);

    loaded.complete('这一页的鞋跟真低呀。');
    await tester.pumpAndSettle();

    expect(find.text('这一页的鞋跟真低呀。'), findsOneWidget);
    expect(find.text('读到哪儿了？'), findsNothing);
  });

  testWidgets('falls back to the default line when the loader is slow', (
    tester,
  ) async {
    final never = Completer<String?>();
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          greetingLoader: () => never.future,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('读到哪儿了？'), findsOneWidget);
  });

  testWidgets('tapping the avatar opens the chat when a handler is given', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          autoGreet: false,
          onOpenChat: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('tapping the bubble opens the chat too', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          greetingLoader: () async => '陪你读这一页。',
          onOpenChat: () => opened++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-bubble')));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('waves while it talks', (tester) async {
    await tester.pumpWidget(_host(const CompanionPresence(height: 160)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    final stage = tester.state<CompanionClipStageState>(
      find.byType(CompanionClipStage),
    );
    expect(stage.clip, companionWaveClip);
  });

  testWidgets('flinches when the reader turns the page', (tester) async {
    final turns = ValueNotifier<int>(0);
    addTearDown(turns.dispose);

    await tester.pumpWidget(
      _host(
        CompanionPresence(height: 160, autoGreet: false, pageTurns: turns),
      ),
    );
    await tester.pumpAndSettle();

    final stage = tester.state<CompanionClipStageState>(
      find.byType(CompanionClipStage),
    );
    expect(stage.clip, companionIdleClip);

    turns.value = 1;
    await tester.pump();
    expect(stage.clip, companionSurpriseClip);
  });

  testWidgets('says a fresh line on every left click', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          autoGreet: false,
          onSpeak: () async {
            calls++;
            return '第 $calls 句';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 句'), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('第 2 句'), findsOneWidget);
    expect(find.text('第 1 句'), findsNothing);
  });

  testWidgets('reads the line the bubble finally shows', (tester) async {
    final said = <String>[];
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          autoGreet: false,
          onSpeak: () async => '你翻到哪儿了？',
          onSpokenLine: said.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    // The thinking line is never read out; only the finished one is.
    expect(said, ['你翻到哪儿了？']);
  });

  testWidgets('reads the greeting once the bubble pops', (tester) async {
    final said = <String>[];
    await tester.pumpWidget(
      _host(CompanionPresence(height: 160, onSpokenLine: said.add)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(said, ['读到哪儿了？']);
  });

  testWidgets('keeps the thinking line when the loader has nothing', (
    tester,
  ) async {    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          autoGreet: false,
          onSpeak: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    expect(find.text('嗯……'), findsOneWidget);
  });

  testWidgets('right click opens the chat instead of toggling the bubble', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          autoGreet: false,
          onSpeak: () async => '你翻到哪儿了？',
          onOpenChat: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('companion-avatar')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('a single-motion skin keeps reacting without extra clips', (
    tester,
  ) async {
    final turns = ValueNotifier<int>(0);
    addTearDown(turns.dispose);
    await tester.pumpWidget(
      _host(
        CompanionPresence(
          height: 160,
          autoGreet: false,
          skin: companionWriterSkin,
          pageTurns: turns,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stage = tester.state<CompanionClipStageState>(
      find.byType(CompanionClipStage),
    );
    expect(stage.clip, companionWriterIdleClip);

    turns.value = 1;
    await tester.pumpAndSettle();
    expect(stage.clip, companionWriterIdleClip);

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    expect(stage.clip, companionWriterIdleClip);
    expect(find.byKey(const Key('companion-bubble')), findsOneWidget);
  });
}
