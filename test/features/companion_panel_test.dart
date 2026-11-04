import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/assistant/unconfigured_assistant_service.dart';
import 'package:hackathon_reading/features/companion/companion_panel.dart';
import 'package:hackathon_reading/tts/tts_config.dart';
import 'package:hackathon_reading/tts/tts_service.dart';

import '../support/fake_tts.dart';

const _ttsConfig = TtsConfig(
  baseUrl: 'http://127.0.0.1:9880',
  voice: 'xll',
  speed: 1,
  volume: 1,
  enabled: true,
  autoSpeak: false,
);

class _FakeAssistant implements AssistantService {
  final List<String> prompts = [];

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage,
  ) async* {
    prompts.add('chat:$userMessage');
    yield '福贵';
    yield '是因为赌博。';
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) async* {
    prompts.add('summary');
    yield '这一章讲福贵败家。';
  }

  @override
  Stream<String> explain(
    String text, {
    required ReadingContext context,
  }) async* {
    yield '解释';
  }

  @override
  Stream<String> translate(String text, {required String targetLang}) async* {
    yield '翻译';
  }
}

Widget _host(
  AssistantService service, {
  FakeTtsClient? client,
  FakeAudioOutput? output,
  Duration speechLength = const Duration(milliseconds: 20),
}) {
  final voice = client ?? FakeTtsClient();
  final speaker = output ?? FakeAudioOutput();
  final tts = TtsService(
    client: voice,
    output: speaker,
    config: () => _ttsConfig,
    tempDirectory: () async => Directory.systemTemp,
    durationOf: (_) => speechLength,
  );
  return _wrap(service, tts);
}

Widget _wrap(AssistantService service, TtsService tts) {
  return ProviderScope(
    overrides: [
      assistantServiceProvider.overrideWith((ref) async => service),
      ttsConfigProvider.overrideWith((ref) async => _ttsConfig),
      ttsServiceProvider.overrideWithValue(tts),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: CompanionPanel(
          bookId: 'book-1',
          chapterIndex: 1,
          chapterTitle: '第二章',
          chapterText: '福贵牵着老牛走在田埂上。',
          chapterCharOffset: 4,
        ),
      ),
    ),
  );
}

Future<void> _ask(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '福贵为什么败家？');
  await tester.tap(find.byTooltip('发送'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unconfigured panel points at the settings page',
      (tester) async {
    await tester.pumpWidget(_host(const UnconfiguredAssistantService()));
    await tester.pumpAndSettle();

    expect(find.textContaining('未配置 AI 服务'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('sending a question streams the answer into the panel',
      (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await _ask(tester);

    expect(fake.prompts, contains('chat:福贵为什么败家？'));
    expect(find.text('福贵为什么败家？'), findsOneWidget);
    expect(find.textContaining('是因为赌博'), findsOneWidget);
  });

  testWidgets('pressing enter sends the question', (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '福贵为什么败家？');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(fake.prompts, contains('chat:福贵为什么败家？'));
    expect(find.text('福贵为什么败家？'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'the box should be cleared once the question is on its way',
    );
  });

  testWidgets('shift+enter keeps the line in the box instead of sending',
      (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(fake.prompts, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '第一行',
    );
  });

  testWidgets('enter while the input method is composing does not send',
      (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nihao');
    tester.widget<TextField>(find.byType(TextField)).controller!.value =
        const TextEditingValue(
      text: 'nihao',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(fake.prompts, isEmpty);
  });

  testWidgets('the summary button streams a chapter summary', (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('总结本章'));
    await tester.pumpAndSettle();

    expect(fake.prompts, contains('summary'));
    expect(find.textContaining('福贵败家'), findsOneWidget);
  });

  testWidgets('the speaker button reads the reply aloud', (tester) async {
    final voice = FakeTtsClient();
    final speaker = FakeAudioOutput();
    final tts = TtsService(
      client: voice,
      output: speaker,
      config: () => _ttsConfig,
      tempDirectory: () async => Directory.systemTemp,
      durationOf: (_) => const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(_wrap(_FakeAssistant(), tts));
    await tester.pumpAndSettle();

    await _ask(tester);
    // The service writes each line to a temp file, so run the tap on the real
    // event loop where file IO can actually complete.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('朗读'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(voice.texts, isNotEmpty);
    expect(voice.texts.first, contains('赌博'));
    expect(voice.voices.first, 'xll');
    expect(speaker.played, isNotEmpty, reason: 'status=${tts.status}');
  });

  testWidgets('the speaker button reads even when auto read is switched off',
      (tester) async {
    final voice = FakeTtsClient();
    final speaker = FakeAudioOutput();
    final tts = TtsService(
      client: voice,
      output: speaker,
      config: () => _ttsConfig.copyWith(enabled: false),
      tempDirectory: () async => Directory.systemTemp,
      durationOf: (_) => const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(_wrap(_FakeAssistant(), tts));
    await tester.pumpAndSettle();

    await _ask(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('朗读'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(voice.texts, isNotEmpty);
    expect(speaker.played, isNotEmpty, reason: 'status=${tts.status}');
  });

  testWidgets('a hush button appears while reading and stops playback',
      (tester) async {
    final speaker = FakeAudioOutput();
    await tester.pumpWidget(
      _host(
        _FakeAssistant(),
        output: speaker,
        speechLength: const Duration(milliseconds: 400),
      ),
    );
    await tester.pumpAndSettle();

    await _ask(tester);
    await tester.tap(find.byTooltip('朗读'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byKey(const Key('companion-hush')), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-hush')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(speaker.stops, greaterThan(0));
    expect(find.byKey(const Key('companion-hush')), findsNothing);
  });

  testWidgets('auto speak stays off until the setting is turned on',
      (tester) async {
    final voice = FakeTtsClient();
    await tester.pumpWidget(_host(_FakeAssistant(), client: voice));
    await tester.pumpAndSettle();

    await _ask(tester);

    expect(voice.texts, isEmpty);
  });
}
