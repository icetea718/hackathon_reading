import 'package:drift/native.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/persona.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/data/repositories/companion_chat_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';
import 'package:hackathon_reading/features/companion/companion_panel.dart';
import 'package:hackathon_reading/features/reader/reader_page.dart';
import 'package:hackathon_reading/tts/audio_output.dart';
import 'package:hackathon_reading/tts/tts_config.dart';
import 'package:hackathon_reading/tts/tts_service.dart';

import '../support/fake_tts.dart';

class _EchoAssistant implements AssistantService {
  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) async* {
    yield '回声';
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

/// Plays nothing and schedules nothing: the reader tests only care that the
/// line reached the voice service, and a real playback timer would outlive them.
class _SilentAudioOutput implements AudioOutput {
  @override
  Future<void> playFile(String path, {Duration? duration}) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

void main() {
  late AppDatabase db;
  late FakeTtsClient voice;

  setUp(() async {
    voice = FakeTtsClient();
    db = AppDatabase(NativeDatabase.memory());
    await BookRepository(db).upsert(Book(
      id: 'b1',
      title: '测试小说',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/b1.txt',
      addedAt: DateTime(2026, 1, 1),
    ));
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
      Chapter(
        id: 'c1',
        bookId: 'b1',
        index: 1,
        title: '第二章',
        startOffset: 6,
        endOffset: 12,
        contentText: '第二章的内容',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpReader(
    WidgetTester tester, {
    bool configured = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // The companion reads its bubble line out loud; keep the audio
          // engine fake and the clips instant so nothing waits on playback.
          ttsServiceProvider.overrideWithValue(
            TtsService(
              client: voice,
              output: _SilentAudioOutput(),
              config: () => TtsConfig.defaults.copyWith(enabled: false),
              tempDirectory: () async => Directory.systemTemp,
              durationOf: (_) => Duration.zero,
            ),
          ),
          if (configured)
            assistantServiceProvider.overrideWith(
              (ref) async => _EchoAssistant(),
            ),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 'b1')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> seedOldThread() async {
    var ids = 0;
    final repo = CompanionChatRepository(db, newId: () => 'id-${ids++}');
    final thread = await repo.createThread(
      bookId: 'b1',
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
  }

  void useWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('wide windows dock the companion beside the page',
      (tester) async {
    useWindow(tester, const Size(1400, 900));
    await pumpReader(tester);

    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-docked')), findsOneWidget);
    expect(find.byKey(const Key('reader-page')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('陪读 · 第一章'), findsOneWidget);
    expect(find.textContaining('未配置 AI 服务'), findsOneWidget);
  });

  testWidgets('the companion knows which page is open', (tester) async {
    useWindow(tester, const Size(1400, 900));
    await pumpReader(tester);

    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();

    final panel =
        tester.widget<CompanionPanel>(find.byType(CompanionPanel));
    expect(panel.chapterPage, 1);
    expect(panel.chapterPageCount, greaterThanOrEqualTo(1));
    expect(panel.currentPageText, contains('第一章的内容'));
    final start = panel.pageStartOffset;
    final end = panel.pageEndOffset;
    expect(start, isNotNull);
    expect(end, isNotNull);
    expect(panel.chapterText.substring(start!, end!), contains('第一章的内容'));
  });

  testWidgets('speaks the bubble line even with 朗读 off', (tester) async {
    useWindow(tester, const Size(1400, 900));
    await pumpReader(tester);

    // The greeting pops 600 ms after the page opens, then asks the voice.
    await tester.pump(const Duration(milliseconds: 700));
    await flush(tester);

    expect(find.text('读到哪儿了？'), findsOneWidget);
    expect(voice.texts, contains('读到哪儿了？'));
    expect(voice.voices, everyElement('zhino'));

    // Let the bubble linger and retract so no timer outlives the test.
    await tester.pump(const Duration(seconds: 7));
    await flush(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('closing the side panel leaves the reader in place',
      (tester) async {
    useWindow(tester, const Size(1400, 900));
    await pumpReader(tester);

    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-docked')), findsNothing);
    expect(find.byKey(const Key('reader-page')), findsOneWidget);
  });

  testWidgets('narrow windows keep the bottom sheet', (tester) async {
    useWindow(tester, const Size(800, 900));
    await pumpReader(tester);

    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-docked')), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.textContaining('陪读 · 第一章'), findsOneWidget);
    expect(find.textContaining('未配置 AI 服务'), findsOneWidget);
  });

  testWidgets('jumping from an old thread opens that thread in its chapter',
      (tester) async {
    await tester.runAsync(seedOldThread);
    useWindow(tester, const Size(1400, 900));
    await pumpReader(tester, configured: true);
    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await flush(tester);
    await tester.tap(find.byKey(const Key('companion-thread-id-0')));
    await flush(tester);
    await tester.tap(find.byKey(const Key('companion-go-to-chapter')));
    await flush(tester);

    expect(find.textContaining('陪读 · 第二章'), findsOneWidget);
    expect(find.text('旧回答'), findsOneWidget);
    expect(find.text('保存在第 2 章，当前为只读'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    // The pet speaks as the thread opens; let the line and its gap drain.
    await tester.pump(const Duration(milliseconds: 60));
    await flush(tester);
  });

  testWidgets('a narrow window closes the sheet and lands on the chapter',
      (tester) async {
    await tester.runAsync(seedOldThread);
    useWindow(tester, const Size(800, 900));
    await pumpReader(tester, configured: true);
    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-tab-history')));
    await flush(tester);
    await tester.tap(find.byKey(const Key('companion-thread-id-0')));
    await flush(tester);
    await tester.tap(find.byKey(const Key('companion-go-to-chapter')));
    await flush(tester);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();
    await flush(tester);
    expect(find.textContaining('陪读 · 第二章'), findsOneWidget);
    expect(find.text('旧回答'), findsOneWidget);
  });
}
