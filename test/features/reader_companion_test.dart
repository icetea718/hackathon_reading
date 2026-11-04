import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/persona.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/features/companion/companion_greeting.dart';
import 'package:hackathon_reading/features/reader/reader_page.dart';
import 'package:hackathon_reading/tts/tts_config.dart';
import 'package:hackathon_reading/tts/tts_service.dart';

import '../support/fake_tts.dart';

class _EchoAssistant implements AssistantService {
  final prompts = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    prompts.add(userMessage);
    return Stream.fromIterable(const ['这一段在讲第一章。']);
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) =>
      const Stream.empty();

  @override
  Stream<String> summarizeChapter(ReadingContext context) => const Stream.empty();

  @override
  Stream<String> translate(String text, {required String targetLang}) =>
      const Stream.empty();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await BookRepository(db).upsert(
      Book(
        id: 'b1',
        title: '测试小说',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/b1.txt',
        addedAt: DateTime(2026, 1, 1),
      ),
    );
    await ChapterRepository(db).replaceForBook('b1', [
      Chapter(
        id: 'c0',
        bookId: 'b1',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: 6,
        contentText: '第一章的内容',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpReader(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides],
        child: const MaterialApp(home: ReaderPage(bookId: 'b1')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the reader opens the companion panel', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();

    expect(find.textContaining('陪读 · 第一章'), findsOneWidget);
    expect(find.textContaining('未配置 AI 服务'), findsOneWidget);
  });

  testWidgets('right clicking the companion opens the bubble chat', (
    tester,
  ) async {
    await pumpReader(tester);

    expect(find.byKey(const Key('companion-avatar')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('companion-avatar')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-chat-panel')), findsOneWidget);
    expect(find.textContaining('陪读 · 第一章'), findsOneWidget);
  });

  testWidgets('closing the bubble chat leaves the reader on the page', (
    tester,
  ) async {
    await pumpReader(tester);

    await tester.tap(
      find.byKey(const Key('companion-avatar')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-chat-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-chat-panel')), findsNothing);
    expect(find.textContaining('第一章的内容'), findsWidgets);
  });

  testWidgets('a question in the bubble chat gets an answer bubble', (
    tester,
  ) async {
    final assistant = _EchoAssistant();
    await pumpReader(
      tester,
      overrides: [assistantServiceProvider.overrideWith((ref) async => assistant)],
    );

    await tester.tap(
      find.byKey(const Key('companion-avatar')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('companion-chat-input')),
      '这一章讲什么？',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(assistant.prompts, ['这一章讲什么？']);
    expect(find.text('这一段在讲第一章。'), findsOneWidget);
  });

  testWidgets('left clicking asks for a line about the page', (tester) async {
    final asked = <CompanionGreetingRequest>[];
    await pumpReader(
      tester,
      overrides: [
        companionGreeterProvider.overrideWithValue((request) async {
          asked.add(request);
          return '这一页在讲第一章的内容。';
        }),
      ],
    );

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    expect(asked, hasLength(1));
    expect(find.text('这一页在讲第一章的内容。'), findsOneWidget);
  });

  testWidgets('two clicks ask twice for a line', (tester) async {
    final asked = <CompanionGreetingRequest>[];
    await pumpReader(
      tester,
      overrides: [
        companionGreeterProvider.overrideWithValue((request) async {
          asked.add(request);
          return '这是第 ${asked.length} 句。';
        }),
      ],
    );

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    expect(asked, hasLength(2));
    expect(find.text('这是第 2 句。'), findsOneWidget);
  });

  testWidgets('reads the bubble line out loud', (tester) async {
    final voice = FakeTtsClient();
    final tts = TtsService(
      client: voice,
      output: FakeAudioOutput(),
      config: () => TtsConfig.defaults,
      tempDirectory: () async => Directory.systemTemp,
      durationOf: (_) => const Duration(milliseconds: 20),
    );
    await pumpReader(
      tester,
      overrides: [
        ttsServiceProvider.overrideWithValue(tts),
        companionGreeterProvider.overrideWithValue(
          (request) async => '这一页在讲第一章的内容。',
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    expect(find.text('这一页在讲第一章的内容。'), findsOneWidget);
    expect(voice.texts.last, '这一页在讲第一章的内容。');
  });
}
