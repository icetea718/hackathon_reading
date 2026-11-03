import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/data/repositories/progress_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/domain/models/reading_progress.dart';
import 'package:hackathon_reading/features/reader/reader_page.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final books = BookRepository(db);
    await books.upsert(Book(
      id: 'b1',
      title: '测试小说',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/b1.txt',
      addedAt: DateTime(2026, 1, 1),
    ));
    await books.upsert(Book(
      id: 'b2',
      title: '空书',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/b2.txt',
      addedAt: DateTime(2026, 1, 2),
    ));

    const texts = ['第一章的内容', '第二章的内容', '第三章的内容'];
    var offset = 0;
    final chapters = <Chapter>[];
    for (var i = 0; i < texts.length; i++) {
      chapters.add(Chapter(
        id: 'c$i',
        bookId: 'b1',
        index: i,
        title: '第${i + 1}章',
        startOffset: offset,
        endOffset: offset + texts[i].length,
        contentText: texts[i],
      ));
      offset += texts[i].length;
    }
    await ChapterRepository(db).replaceForBook('b1', chapters);
    await ProgressRepository(db).save(ReadingProgress(
      bookId: 'b1',
      anchor: const ReadingAnchor(charOffset: 8),
      percent: 8 / 18,
      updatedAt: DateTime(2026, 1, 1),
    ));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpReader(WidgetTester tester, String bookId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: ReaderPage(bookId: bookId)),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('restores the chapter from saved progress', (tester) async {
    await pumpReader(tester, 'b1');
    expect(find.textContaining('第二章的内容'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('TOC lists chapters and jumps to a selected one', (tester) async {
    await pumpReader(tester, 'b1');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('第1章'), findsOneWidget);
    expect(find.text('第2章'), findsOneWidget);
    expect(find.text('第3章'), findsOneWidget);

    await tester.tap(find.text('第3章'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第三章的内容'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('shows a message when the book has no chapters', (tester) async {
    await pumpReader(tester, 'b2');
    expect(find.text('这本书暂时没有可显示的章节'), findsOneWidget);
    await disposeApp(tester);
  });
}
