import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/progress_repository.dart';
import 'package:coread/data/storage/book_storage.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/reading_progress.dart';
import 'package:coread/features/library/book_card.dart';
import 'package:coread/features/library/book_cover.dart';
import 'package:coread/features/library/library_page.dart';

Book mkBook(
  String id, {
  required String title,
  String author = '',
  BookFormat format = BookFormat.txt,
  String? coverPath,
  bool comic = false,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    sourcePath: 'C:/books/$id.${format.name}',
    coverPath: coverPath,
    contentHash: 'hash-$id',
    comic: comic,
    addedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('book_grid_test');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  /// Drift stream notifications hold the executor until the fake clock
  /// advances, so multi-write actions need frames between real-time slices.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() => tester.tap(finder));
    for (var round = 0; round < 6; round++) {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> pumpShelf(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bookStorageProvider.overrideWith(
            (ref) async => BookStorage(Directory('${temp.path}/books')),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: BookshelfView())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeShelf(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> seed(WidgetTester tester, Book book) async {
    await tester.runAsync(() => BookRepository(db).upsert(book));
  }

  Finder card(String id) => find.byKey(Key('book-card-$id'));

  Finder cardMenu(String id) =>
      find.descendant(of: card(id), matching: find.byTooltip('更多'));

  testWidgets('empty shelf shows the empty state and import action', (
    tester,
  ) async {
    await pumpShelf(tester);

    expect(find.text('还没有书'), findsOneWidget);
    expect(find.text('导入第一本书'), findsOneWidget);
    await disposeShelf(tester);
  });

  testWidgets('cards show title and progress without an author line', (
    tester,
  ) async {
    await seed(tester, mkBook('b1', title: '三体', author: '刘慈欣'));
    await seed(tester, mkBook('b2', title: '红楼梦'));
    await seed(tester, mkBook('b3', title: '论语', author: '孔子'));
    await tester.runAsync(
      () => ProgressRepository(db).save(
        ReadingProgress(
          bookId: 'b1',
          anchor: const ReadingAnchor(charOffset: 10),
          percent: 0.62,
          updatedAt: DateTime(2026, 2, 1),
        ),
      ),
    );
    await pumpShelf(tester);

    expect(find.byType(BookCard), findsNWidgets(3));
    expect(find.text('三体'), findsWidgets);
    expect(find.text('刘慈欣'), findsNothing);
    expect(find.text('未知作者'), findsNothing);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('未开始'), findsNWidgets(2));
    await disposeShelf(tester);
  });

  testWidgets('search filters, clears, and reports no matches', (tester) async {
    await seed(tester, mkBook('b1', title: '三体', author: '刘慈欣'));
    await seed(tester, mkBook('b2', title: '红楼梦', author: '曹雪芹'));
    await pumpShelf(tester);
    final field = find.byKey(const Key('search-field'));

    await tester.enterText(field, '三');
    await tester.pumpAndSettle();
    expect(card('b1'), findsOneWidget);
    expect(card('b2'), findsNothing);

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(card('b1'), findsOneWidget);
    expect(card('b2'), findsOneWidget);

    await tester.enterText(field, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的书'), findsOneWidget);
    expect(find.text('清空搜索'), findsOneWidget);

    await tester.tap(find.text('清空搜索'));
    await tester.pumpAndSettle();
    expect(card('b1'), findsOneWidget);
    expect(card('b2'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await disposeShelf(tester);
  });

  testWidgets('card menu disables distill for PDF and comic books', (
    tester,
  ) async {
    await seed(tester, mkBook('b1', title: '三体', author: '刘慈欣'));
    await seed(tester, mkBook('b2', title: '论文', format: BookFormat.pdf));
    await seed(tester, mkBook(
      'b3',
      title: '漫画',
      format: BookFormat.epub,
      comic: true,
    ));
    await pumpShelf(tester);

    await tester.tap(cardMenu('b1'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(find.text('添加到分类…'), findsOneWidget);
    expect(find.text('蒸馏'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tapAt(const Offset(400, 590));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsNothing);

    await tester.tap(cardMenu('b2'));
    await tester.pumpAndSettle();
    final distill = tester.widget<PopupMenuItem<dynamic>>(
      find.ancestor(
        of: find.text('蒸馏'),
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      ),
    );
    expect(distill.enabled, isFalse);

    await tester.tapAt(const Offset(400, 590));
    await tester.pumpAndSettle();
    await tester.tap(cardMenu('b3'));
    await tester.pumpAndSettle();
    final comicDistill = tester.widget<PopupMenuItem<dynamic>>(
      find.ancestor(
        of: find.text('蒸馏'),
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      ),
    );
    expect(comicDistill.enabled, isFalse);
    await disposeShelf(tester);
  });

  testWidgets('deleting a book confirms and removes the card', (tester) async {
    await seed(tester, mkBook('b1', title: '三体'));
    await pumpShelf(tester);

    await tester.tap(cardMenu('b1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除这本书？'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );

    expect(card('b1'), findsNothing);
    final books = await tester.runAsync(() => BookRepository(db).getAll());
    expect(books, isEmpty);
    await disposeShelf(tester);
  });

  testWidgets('a missing cover file falls back to the generated cover', (
    tester,
  ) async {
    final book = mkBook(
      'b1',
      title: '三体',
      coverPath: '${temp.path}/missing-cover.jpg',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 160,
            child: BookCover(book: book),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('三体'), findsOneWidget);
  });
}
