import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
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

  Future<void> pumpReader(WidgetTester tester, FakeAssistantService service) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          assistantServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 'tb')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('translating the whole chapter opens the popup', (tester) async {
    final service = FakeAssistantService(chunks: const ['夜很冷，路很空。']);
    await pumpReader(tester, service);

    await tester.tap(find.byTooltip('翻译本章'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationDialog), findsOneWidget);
    expect(find.text('翻译本章：第一章'), findsOneWidget);
    expect(find.text('夜很冷，路很空。'), findsOneWidget);
    expect(service.translatedSources.single, chapterText);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the chapter translate button is always reachable', (
    tester,
  ) async {
    await pumpReader(tester, FakeAssistantService());

    expect(find.byTooltip('翻译本章'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
