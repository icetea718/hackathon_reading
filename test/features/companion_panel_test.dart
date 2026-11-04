import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/persona.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/assistant/unconfigured_assistant_service.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/companion_chat_repository.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';
import 'package:hackathon_reading/features/companion/companion_panel.dart';
import 'package:hackathon_reading/features/memory_book/memory_book_providers.dart';
import 'package:hackathon_reading/memory_book/memory_book_models.dart';
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
  final List<PersonaMode> personas = [];
  List<ChatMessage>? lastHistory;
  ReadingContext? lastContext;

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) async* {
    prompts.add('chat:$userMessage');
    personas.add(persona);
    lastHistory = List.of(history);
    lastContext = context;
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

class _ControlledAssistant implements AssistantService {
  final controllers = <StreamController<String>>[];
  final histories = <List<ChatMessage>>[];
  final contexts = <ReadingContext>[];

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    contexts.add(context);
    histories.add(List.of(history));
    final controller = StreamController<String>();
    controllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) async* {
    yield '摘要';
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

class _FailingAssistant extends _FakeAssistant {
  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) async* {
    prompts.add('chat:$userMessage');
    yield '半截';
    throw Exception('boom');
  }
}

Widget _host(
  AssistantService service, {
  FakeTtsClient? client,
  FakeAudioOutput? output,
  Duration speechLength = const Duration(milliseconds: 20),
  AppDatabase? db,
  ValueNotifier<int>? chapter,
  int chapterIndex = 1,
  ValueChanged<int>? onGoToChapter,
  int? chapterPage,
  int? chapterPageEnd,
  int? chapterPageCount,
  int? bookPage,
  int? bookPageTotal,
  int? pageStartOffset,
  int? pageEndOffset,
  String currentPageText = '',
  Stream<List<MemoryBook>>? memoryBooks,
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
  return _wrap(
    service,
    tts,
    db: db,
    chapter: chapter,
    chapterIndex: chapterIndex,
    onGoToChapter: onGoToChapter,
    chapterPage: chapterPage,
    chapterPageEnd: chapterPageEnd,
    chapterPageCount: chapterPageCount,
    bookPage: bookPage,
    bookPageTotal: bookPageTotal,
    pageStartOffset: pageStartOffset,
    pageEndOffset: pageEndOffset,
    currentPageText: currentPageText,
    memoryBooks: memoryBooks,
  );
}

Widget _wrap(
  AssistantService service,
  TtsService tts, {
  AppDatabase? db,
  ValueNotifier<int>? chapter,
  int chapterIndex = 1,
  ValueChanged<int>? onGoToChapter,
  int? chapterPage,
  int? chapterPageEnd,
  int? chapterPageCount,
  int? bookPage,
  int? bookPageTotal,
  int? pageStartOffset,
  int? pageEndOffset,
  String currentPageText = '',
  Stream<List<MemoryBook>>? memoryBooks,
}) {
  final database = db ?? AppDatabase(NativeDatabase.memory());
  if (db == null) addTearDown(database.close);
  final chapterNotifier = chapter ?? ValueNotifier<int>(chapterIndex);
  if (chapter == null) addTearDown(chapterNotifier.dispose);
  return ProviderScope(
    overrides: [
      assistantServiceProvider.overrideWith((ref) async => service),
      appDatabaseProvider.overrideWithValue(database),
      ttsConfigProvider.overrideWith((ref) async => _ttsConfig),
      ttsServiceProvider.overrideWithValue(tts),
      if (memoryBooks != null)
        memoryBookListProvider.overrideWith((ref) => memoryBooks),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: chapterNotifier,
          builder: (context, index, _) => CompanionPanel(
            bookId: 'book-1',
            chapterIndex: index,
            chapterTitle: '第${index + 1}章',
            chapterText: '福贵牵着老牛走在田埂上。',
            chapterCharOffset: 4,
            chapterPage: chapterPage,
            chapterPageEnd: chapterPageEnd,
            chapterPageCount: chapterPageCount,
            bookPage: bookPage,
            bookPageTotal: bookPageTotal,
            pageStartOffset: pageStartOffset,
            pageEndOffset: pageEndOffset,
            currentPageText: currentPageText,
            onGoToChapter: onGoToChapter,
          ),
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _flush(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _ask(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '福贵为什么败家？');
  await tester.tap(find.byTooltip('发送'));
  await _settle(tester);
}

/// Taps the speaker and waits on the real event loop until playback starts.
/// Synthesis writes temp files, so a fixed sleep races on a loaded machine.
Future<void> _tapSpeak(WidgetTester tester, FakeAudioOutput speaker) async {
  await tester.runAsync(() async {
    await tester.tap(find.byTooltip('朗读'));
    for (var i = 0; i < 80 && speaker.played.isEmpty; i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unconfigured panel points at the settings page',
      (tester) async {
    await tester.pumpWidget(_host(const UnconfiguredAssistantService()));
    await _settle(tester);

    expect(find.textContaining('未配置 AI 服务'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('the memory hint above the chat can be closed',
      (tester) async {
    await tester.pumpWidget(_host(_FakeAssistant()));
    await _settle(tester);

    expect(find.byKey(const Key('companion-memory-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-memory-chip-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-memory-chip')), findsNothing);
  });

  testWidgets('sending a question streams the answer into the panel',
      (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    await _ask(tester);

    expect(fake.prompts, contains('chat:福贵为什么败家？'));
    expect(find.text('福贵为什么败家？'), findsOneWidget);
    expect(find.textContaining('是因为赌博'), findsOneWidget);
  });

  testWidgets('the request carries the page being read', (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(
      fake,
      chapterPage: 3,
      chapterPageEnd: 4,
      chapterPageCount: 20,
      bookPage: 42,
      bookPageTotal: 300,
      currentPageText: '这一页的正文。',
    ));
    await _settle(tester);

    await _ask(tester);

    final context = fake.lastContext!;
    expect(context.chapterPage, 3);
    expect(context.chapterPageEnd, 4);
    expect(context.chapterPageCount, 20);
    expect(context.bookPage, 42);
    expect(context.bookPageTotal, 300);
    expect(context.currentPageText, '这一页的正文。');
  });

  testWidgets('spoilers stay off until the reader turns them on',
      (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(
      fake,
      chapterPage: 3,
      pageStartOffset: 100,
      pageEndOffset: 200,
    ));
    await _settle(tester);

    await _ask(tester);

    expect(fake.lastContext!.allowSpoilers, isFalse);
    expect(fake.lastContext!.pageStartOffset, 100);
    expect(fake.lastContext!.pageEndOffset, 200);

    await tester.tap(find.byKey(const Key('companion-spoiler-toggle')));
    await tester.pumpAndSettle();
    await _ask(tester);

    expect(fake.lastContext!.allowSpoilers, isTrue);
  });

  testWidgets('pressing enter sends the question', (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '福贵为什么败家？');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

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
    await _settle(tester);

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
    await _settle(tester);

    await tester.enterText(find.byType(TextField), 'nihao');
    tester.widget<TextField>(find.byType(TextField)).controller!.value =
        const TextEditingValue(
      text: 'nihao',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

    expect(fake.prompts, isEmpty);
  });

  testWidgets('the summary button streams a chapter summary', (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    await tester.tap(find.text('总结本章'));
    await _settle(tester);

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
    await _settle(tester);

    await _ask(tester);
    await _tapSpeak(tester, speaker);

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
    await _settle(tester);

    await _ask(tester);
    await _tapSpeak(tester, speaker);

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
    await _settle(tester);

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
    await _settle(tester);

    await _ask(tester);

    expect(voice.texts, isEmpty);
  });

  testWidgets('a saved conversation reopens with the panel', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late CompanionThread thread;
    await tester.runAsync(() async {
      final repo = CompanionChatRepository(db);
      thread = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '福贵',
      );
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '福贵为什么败家？',
      );
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.assistant,
        content: '因为赌博。',
      );
    });

    await tester.pumpWidget(_host(_FakeAssistant(), db: db));
    await _settle(tester);

    expect(find.text('福贵为什么败家？'), findsOneWidget);
    expect(find.text('因为赌博。'), findsOneWidget);
  });

  testWidgets('the question is stored before the reply finishes',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _ControlledAssistant();
    await tester.pumpWidget(_host(fake, db: db));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '福贵为什么败家？');
    await tester.tap(find.byTooltip('发送'));
    await _flush(tester);

    final rows = await tester.runAsync(
      () => CompanionChatRepository(db).threadsForBook('book-1'),
    );
    expect(rows, hasLength(1));
    final stored = await tester.runAsync(
      () => CompanionChatRepository(db).messagesForThread(rows!.single.id),
    );
    expect(stored!.map((m) => m.content), contains('福贵为什么败家？'));
    expect(stored.where((m) => m.role == CompanionRole.assistant), isEmpty);
  });

  testWidgets('the model sees the last eight messages and the prior digest',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeAssistant();
    await tester.runAsync(() async {
      final repo = CompanionChatRepository(db);
      final prior = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 0,
        chapterTitle: '第一章',
        title: '前文',
      );
      await repo.appendMessage(
        threadId: prior.id,
        role: CompanionRole.user,
        content: '前文问答',
      );
      final later = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 3,
        chapterTitle: '第四章',
        title: '未来',
      );
      await repo.appendMessage(
        threadId: later.id,
        role: CompanionRole.user,
        content: '未来剧透',
      );
      final current = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '当前',
      );
      for (var i = 1; i <= 10; i++) {
        await repo.appendMessage(
          threadId: current.id,
          role: i.isOdd ? CompanionRole.user : CompanionRole.assistant,
          content: 'm$i',
        );
      }
    });

    await tester.pumpWidget(_host(fake, db: db));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '新问题');
    await tester.tap(find.byTooltip('发送'));
    await _settle(tester);

    expect(fake.lastHistory, hasLength(8));
    expect(fake.lastHistory!.first.content, 'm3');
    expect(fake.lastHistory!.last.content, 'm10');
    expect(
      fake.lastHistory!.where((m) => m.content == '新问题'),
      isEmpty,
      reason: 'the current question must only be sent once',
    );
    expect(fake.lastContext!.companionMemory, contains('前文问答'));
    expect(fake.lastContext!.companionMemory, isNot(contains('未来剧透')));
  });

  testWidgets('switching chapters drops the reply that was still streaming',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _ControlledAssistant();
    final chapter = ValueNotifier(1);
    addTearDown(chapter.dispose);
    await tester.pumpWidget(_host(fake, db: db, chapter: chapter));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '旧章问题');
    await tester.tap(find.byTooltip('发送'));
    await _flush(tester);

    chapter.value = 2;
    await _flush(tester);

    fake.controllers.last.add('迟到的回答');
    await fake.controllers.last.close();
    await _settle(tester);

    expect(find.text('迟到的回答'), findsNothing);
    final rows = await tester.runAsync(
      () => CompanionChatRepository(db).threadsForBook('book-1'),
    );
    for (final thread in rows!) {
      final messages = await tester.runAsync(
        () => CompanionChatRepository(db).messagesForThread(thread.id),
      );
      expect(messages!.where((m) => m.content == '迟到的回答'), isEmpty);
    }
  });

  testWidgets('a failed reply keeps the question and drops the partial answer',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(_host(_FailingAssistant(), db: db));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '会失败的问题');
    await tester.tap(find.byTooltip('发送'));
    await _settle(tester);

    final repo = CompanionChatRepository(db);
    final threads = await tester.runAsync(() => repo.threadsForBook('book-1'));
    final stored = await tester.runAsync(
      () => repo.messagesForThread(threads!.single.id),
    );
    expect(stored!.map((m) => m.content), ['会失败的问题']);
    expect(stored.where((m) => m.role == CompanionRole.assistant), isEmpty);
    expect(find.textContaining('出错了'), findsOneWidget);
    expect(find.textContaining('半截'), findsNothing);
  });

  testWidgets('a new conversation is renamed after its first message',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(_host(_FakeAssistant(), db: db));
    await _settle(tester);

    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('companion-new-thread')));
    await _settle(tester);

    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await _settle(tester);
    expect(find.widgetWithText(TextButton, '新对话'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '新对话'), findsOneWidget);
    expect(find.textContaining('共 0 条'), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-tab-chat')));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '你好世界');
    await tester.tap(find.byTooltip('发送'));
    await _settle(tester);

    final rows = await tester.runAsync(
      () => CompanionChatRepository(db).threadsForBook('book-1'),
    );
    expect(rows!.single.title, '你好世界');
  });

  testWidgets('deleting the only thread returns to an empty chat',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late CompanionThread thread;
    await tester.runAsync(() async {
      final repo = CompanionChatRepository(db);
      thread = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '唯一对话',
      );
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '旧问题',
      );
    });
    await tester.pumpWidget(_host(_FakeAssistant(), db: db));
    await _settle(tester);

    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await _settle(tester);
    await tester.tap(
      find.byKey(Key('companion-thread-menu-${thread.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-menu-delete')));
    await _settle(tester);

    final rows = await tester.runAsync(
      () => CompanionChatRepository(db).threadsForBook('book-1'),
    );
    expect(rows, isEmpty);
    expect(find.text('还没有对话'), findsOneWidget);
  });

  testWidgets('deleting the open thread falls back to the latest one',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late CompanionThread older;
    late CompanionThread newer;
    await tester.runAsync(() async {
      var clock = DateTime(2026, 11, 4, 9);
      final repo = CompanionChatRepository(db, now: () => clock);
      older = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '旧对话',
      );
      await repo.appendMessage(
        threadId: older.id,
        role: CompanionRole.user,
        content: '旧对话的问题',
      );
      clock = DateTime(2026, 11, 4, 10);
      newer = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '新对话',
      );
      await repo.appendMessage(
        threadId: newer.id,
        role: CompanionRole.user,
        content: '新对话的问题',
      );
    });
    await tester.pumpWidget(_host(_FakeAssistant(), db: db));
    await _settle(tester);

    expect(find.text('新对话的问题'), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await _settle(tester);
    await tester.tap(find.byKey(Key('companion-thread-menu-${newer.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-menu-delete')));
    await _settle(tester);

    await tester.tap(find.byKey(const Key('companion-tab-chat')));
    await _settle(tester);

    expect(find.text('旧对话的问题'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('deleting a thread stops the reply it was generating',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _ControlledAssistant();
    await tester.pumpWidget(_host(fake, db: db));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '会迟到的提问');
    await tester.tap(find.byTooltip('发送'));
    await _flush(tester);

    final rows = await tester.runAsync(
      () => CompanionChatRepository(db).threadsForBook('book-1'),
    );
    final oldId = rows!.single.id;

    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await _settle(tester);
    await tester.tap(find.byKey(Key('companion-thread-menu-$oldId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-menu-delete')));
    await _flush(tester);

    fake.controllers.last.add('迟到的回答');
    await fake.controllers.last.close();
    await _settle(tester);

    expect(find.text('迟到的回答'), findsNothing);
    final left = await tester.runAsync(
      () => CompanionChatRepository(db).threadsForBook('book-1'),
    );
    expect(left, isEmpty);
    final messages = await tester.runAsync(
      () => CompanionChatRepository(db).messagesForThread(oldId),
    );
    expect(messages, isEmpty);
  });

  testWidgets('an old chapter thread opens read-only with a jump button',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      var ids = 0;
      final repo = CompanionChatRepository(db, newId: () => 'id-${ids++}');
      final old = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '旧对话',
      );
      await repo.appendMessage(
        threadId: old.id,
        role: CompanionRole.user,
        content: '旧问题',
      );
      await repo.appendMessage(
        threadId: old.id,
        role: CompanionRole.assistant,
        content: '旧回答',
      );
    });
    int? jumped;

    await tester.pumpWidget(
      _host(
        _FakeAssistant(),
        db: db,
        chapterIndex: 2,
        onGoToChapter: (index) => jumped = index,
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('companion-thread-id-0')));
    await _settle(tester);

    expect(find.text('保存在第 2 章，当前为只读'), findsOneWidget);
    expect(find.text('旧问题'), findsOneWidget);
    expect(find.text('旧回答'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('总结本章'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '总结本章'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('companion-go-to-chapter')));
    expect(jumped, 1);
  });

  testWidgets('an unconfigured panel still browses saved history',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late CompanionThread thread;
    await tester.runAsync(() async {
      final repo = CompanionChatRepository(db);
      thread = await repo.createThread(
        bookId: 'book-1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '旧对话',
      );
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '旧问题',
      );
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.assistant,
        content: '旧回答',
      );
    });
    await tester.pumpWidget(
      _host(const UnconfiguredAssistantService(), db: db),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await _settle(tester);
    await tester.tap(find.byKey(Key('companion-thread-${thread.id}')));
    await _settle(tester);

    expect(find.text('旧问题'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('the header opens the memory book sheet', (tester) async {
    await tester.pumpWidget(
      _host(_FakeAssistant(), memoryBooks: Stream.value(const [])),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const Key('companion-memory')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-memory-sheet')), findsOneWidget);
    expect(find.text('把这一页画成插画'), findsOneWidget);
  });

  testWidgets('the memory sheet prefers the page text over the chapter',
      (tester) async {
    await tester.pumpWidget(
      _host(
        _FakeAssistant(),
        currentPageText: '这一页的正文。',
        memoryBooks: Stream.value(const []),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const Key('companion-memory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-memory-generate')));
    await tester.pumpAndSettle();

    expect(find.text('这一页的正文。'), findsOneWidget);
  });

  group('persona', () {
    testWidgets('the chip names the voice the reader is in', (tester) async {
      await tester.pumpWidget(_host(_FakeAssistant()));
      await _settle(tester);

      expect(find.byKey(const Key('companion-mode-pill')), findsOneWidget);
      expect(find.text(PersonaMode.gentle.shortLabel), findsOneWidget);
    });

    testWidgets('the chip opens the chooser with both voices', (tester) async {
      await tester.pumpWidget(_host(_FakeAssistant()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('companion-mode-pill')));
      await tester.pumpAndSettle();

      expect(find.text('陪读模式'), findsOneWidget);
      for (final mode in PersonaMode.values) {
        expect(find.byKey(Key('persona-option-${mode.id}')), findsOneWidget);
        expect(find.text('“${mode.sample}”'), findsOneWidget);
      }
    });

    testWidgets('picking a voice closes the chooser and says so',
        (tester) async {
      await tester.pumpWidget(_host(_FakeAssistant()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('companion-mode-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('persona-option-debate')));
      await _settle(tester);

      expect(find.text('陪读模式'), findsNothing);
      expect(find.text('已切到${PersonaMode.debate.label}'), findsOneWidget);
      expect(find.text(PersonaMode.debate.shortLabel), findsOneWidget);
    });

    testWidgets('the next question goes out in the chosen voice',
        (tester) async {
      final assistant = _FakeAssistant();
      await tester.pumpWidget(_host(assistant));
      await _settle(tester);
      await _ask(tester);
      expect(assistant.personas.last, PersonaMode.gentle);
      expect(find.text('福贵是因为赌博。'), findsOneWidget);

      await tester.tap(find.byKey(const Key('companion-mode-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('persona-option-debate')));
      await _settle(tester);
      expect(find.text('福贵是因为赌博。'), findsOneWidget);

      await _ask(tester);
      expect(assistant.personas.last, PersonaMode.debate);
      expect(find.text('已切到${PersonaMode.debate.label}'), findsNothing);
    });

    testWidgets('picking the voice already in use stays quiet', (tester) async {
      await tester.pumpWidget(_host(_FakeAssistant()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('companion-mode-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('persona-option-gentle')));
      await _settle(tester);

      expect(find.text('已切到${PersonaMode.gentle.label}'), findsNothing);
    });
  });
}
