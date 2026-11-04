import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/app.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/category_repository.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/domain/models/book.dart';

Book mkBook(String id, {required String title}) => Book(
  id: id,
  title: title,
  author: '',
  format: BookFormat.txt,
  sourcePath: 'C:/books/$id.txt',
  contentHash: 'hash-$id',
  addedAt: DateTime(2026, 1, 1),
);

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('drag_drop_test');
    db = AppDatabase(NativeDatabase.memory());
    await BookRepository(db).upsert(mkBook('b1', title: '三体'));
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bookStorageProvider.overrideWith(
            (ref) async => BookStorage(Directory('${temp.path}/books')),
          ),
        ],
        child: const BookApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> withApp(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    try {
      await pumpApp(tester);
      await body();
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Future<void> dragCardTo(
    WidgetTester tester,
    String bookId,
    String targetKey,
  ) async {
    final from = tester.getCenter(find.byKey(Key('book-card-$bookId')));
    final to = tester.getCenter(find.byKey(Key(targetKey)));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<List<BookCategoryRecord>> memberships(WidgetTester tester) async {
    final rows = await tester.runAsync(
      () => db.select(db.bookCategories).get(),
    );
    return rows!;
  }

  testWidgets('dropping a book on a category adds the membership', (
    tester,
  ) async {
    late String sciFiId;
    await tester.runAsync(() async {
      sciFiId = (await CategoryRepository(db).create('科幻')).id;
    });

    await withApp(tester, () async {
      await dragCardTo(tester, 'b1', 'category-drop-$sciFiId');

      final rows = await memberships(tester);
      expect(rows, hasLength(1));
      expect(rows.single.bookId, 'b1');
      expect(rows.single.categoryId, sciFiId);
    });
  });

  testWidgets('dropping the same book twice reports the duplicate', (
    tester,
  ) async {
    late String sciFiId;
    await tester.runAsync(() async {
      sciFiId = (await CategoryRepository(db).create('科幻')).id;
      await CategoryRepository(db).addBook('b1', sciFiId);
    });

    await withApp(tester, () async {
      await dragCardTo(tester, 'b1', 'category-drop-$sciFiId');

      expect(find.text('已经在「科幻」中'), findsOneWidget);
      expect(await memberships(tester), hasLength(1));
    });
  });

  testWidgets('dropping on new category creates it and adds the book', (
    tester,
  ) async {
    await withApp(tester, () async {
      await dragCardTo(tester, 'b1', 'category-drop-new');
      expect(find.text('新建分类'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('category-name-field')),
        '历史',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('category-name-confirm')));
      await tester.pumpAndSettle();

      final categories = await tester.runAsync(
        () => CategoryRepository(db).getAll(),
      );
      expect(categories!.single.name, '历史');
      final rows = await memberships(tester);
      expect(rows.single.bookId, 'b1');
      expect(rows.single.categoryId, categories.single.id);
    });
  });

  testWidgets('cancelling the new category dialog adds nothing', (tester) async {
    await withApp(tester, () async {
      await dragCardTo(tester, 'b1', 'category-drop-new');
      expect(find.text('新建分类'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      final categories = await tester.runAsync(
        () => CategoryRepository(db).getAll(),
      );
      expect(categories, isEmpty);
      expect(await memberships(tester), isEmpty);
    });
  });
}
