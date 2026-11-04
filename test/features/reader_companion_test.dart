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

void main() {
  late AppDatabase db;

  setUp(() async {
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
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('the reader opens the companion panel', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ReaderPage(bookId: 'b1')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();

    expect(find.textContaining('陪读 · 第一章'), findsOneWidget);
    expect(find.textContaining('未配置 AI 服务'), findsOneWidget);
  });

  testWidgets('tapping the companion avatar opens the panel too', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ReaderPage(bookId: 'b1')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('companion-avatar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    expect(find.textContaining('陪读 · 第一章'), findsOneWidget);
  });
}
