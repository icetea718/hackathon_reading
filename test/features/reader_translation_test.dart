import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/assistant/translation_exception.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/features/reader/reader_page.dart';
import 'package:hackathon_reading/features/reader/translation_dialog.dart';

import '../support/fake_assistant_service.dart';

void main() {
  late AppDatabase db;

  const chapterText = 'The night was cold and the road was empty.';
  const translated = '夜晚寒冷，道路空旷。';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await BookRepository(db).upsert(Book(
      id: 'tb',
      title: '英文小说',
      author: 'Someone',
      format: BookFormat.txt,
      sourcePath: 'C:/books/tb.txt',
      addedAt: DateTime(2026, 2, 1),
    ));
    await ChapterRepository(db).replaceForBook('tb', [
      Chapter(
        id: 'tb-c0',
        bookId: 'tb',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: chapterText.length,
        contentText: chapterText,
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpReader(
    WidgetTester tester,
    FakeAssistantService service,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          translationServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 'tb')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('translating the chapter replaces the page and toggles back', (
    tester,
  ) async {
    final service = FakeAssistantService(chunks: const [translated]);
    await pumpReader(tester, service);

    await tester.tap(find.byTooltip('翻译本章'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationDialog), findsNothing);
    expect(find.textContaining(translated), findsOneWidget);
    expect(find.textContaining('The night was cold'), findsNothing);
    expect(service.translatedSources.single, chapterText);

    await tester.tap(find.byTooltip('查看原文'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The night was cold'), findsOneWidget);
    expect(find.textContaining(translated), findsNothing);
  });

  testWidgets('a wide window keeps the original left and translation right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpReader(
      tester,
      FakeAssistantService(translateText: (source) => translated),
    );

    await tester.tap(find.byTooltip('翻译本章'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationDialog), findsNothing);
    expect(find.textContaining('The night was cold'), findsOneWidget);
    expect(find.textContaining(translated), findsOneWidget);
  });

  testWidgets('translation spreads advance one original page at a time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final longText = List.generate(
      30,
      (index) => 'Line ${index + 1} ${'word ' * 24}',
    ).join('\n');
    await ChapterRepository(db).replaceForBook('tb', [
      Chapter(
        id: 'tb-c0',
        bookId: 'tb',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: longText.length,
        contentText: longText,
      ),
    ]);

    await pumpReader(
      tester,
      FakeAssistantService(translateText: (source) => '译文'),
    );
    await tester.tap(find.byTooltip('翻译本章'));
    await tester.pumpAndSettle();

    String footer() => tester
        .widget<Text>(find.textContaining(RegExp(r'^第 \d+ / ')))
        .data!;

    expect(footer(), contains('第 1 /'));
    expect(footer(), isNot(contains('–')));

    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();

    expect(footer(), contains('第 2 /'));
  });

  testWidgets('a failed translation leaves the page untouched', (tester) async {
    await pumpReader(
      tester,
      FakeAssistantService(
        error: const TranslationException('网络连接失败，请检查网络后重试'),
      ),
    );

    await tester.tap(find.byTooltip('翻译本章'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationDialog), findsNothing);
    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(find.textContaining('The night was cold'), findsOneWidget);
    expect(find.byTooltip('翻译本章'), findsOneWidget);
  });

  testWidgets('the chapter translate button is always reachable', (
    tester,
  ) async {
    await pumpReader(tester, FakeAssistantService());

    expect(find.byTooltip('翻译本章'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
