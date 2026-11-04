import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late String sciFiId;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('manage_mode_test');
    db = AppDatabase(NativeDatabase.memory());
    final books = BookRepository(db);
    await books.upsert(mkBook('b1', title: '三体'));
    await books.upsert(mkBook('b2', title: '红楼梦'));
    sciFiId = (await CategoryRepository(db).create('科幻')).id;
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

  /// Drift stream notifications hold the executor until the fake clock
  /// advances, and deleting a book touches real files; alternate frames with
  /// real-time slices instead of one long wait.
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

  Finder card(String id) => find.byKey(Key('book-card-$id'));

  ButtonStyleButton buttonWithText(WidgetTester tester, String text) {
    return tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      ),
    );
  }

  Future<List<BookCategoryRecord>> memberships(WidgetTester tester) async {
    final rows = await tester.runAsync(
      () => db.select(db.bookCategories).get(),
    );
    return rows!;
  }

  testWidgets('manage mode shows checkboxes and disables empty actions', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.text('已选 0 本'), findsOneWidget);
      expect(buttonWithText(tester, '添加到分类…').onPressed, isNull);
      expect(buttonWithText(tester, '移出当前分类').onPressed, isNull);
      expect(buttonWithText(tester, '删除').onPressed, isNull);
    });
  });

  testWidgets('selecting cards enables actions and opens the picker', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      await tester.tap(card('b1'));
      await tester.pumpAndSettle();
      await tester.tap(card('b2'));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 本'), findsOneWidget);
      expect(buttonWithText(tester, '删除').onPressed, isNotNull);

      await tester.tap(find.text('添加到分类…'));
      await tester.pumpAndSettle();
      expect(find.text('添加到分类'), findsOneWidget);
    });
  });

  testWidgets('removing from the current category leaves other membership', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.runAsync(
        () => CategoryRepository(db).addBook('b1', sciFiId),
      );
      await pumpApp(tester);

      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      await tester.tap(card('b1'));
      await tester.pumpAndSettle();
      expect(buttonWithText(tester, '移出当前分类').onPressed, isNull);

      await tester.tap(find.byKey(Key('category-row-$sciFiId')));
      await tester.pumpAndSettle();
      expect(buttonWithText(tester, '移出当前分类').onPressed, isNotNull);

      await tapAndSettle(tester, find.text('移出当前分类'));
      expect(await memberships(tester), isEmpty);
    });
  });

  testWidgets('deleting selected books confirms and exits manage mode', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      await tester.tap(card('b1'));
      await tester.pumpAndSettle();
      await tester.tap(card('b2'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除选中的 2 本书？'), findsOneWidget);

      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );

      expect(card('b1'), findsNothing);
      expect(card('b2'), findsNothing);
      expect(find.text('已选 0 本'), findsNothing);
      final books = await tester.runAsync(() => BookRepository(db).getAll());
      expect(books, isEmpty);
    });
  });

  testWidgets('escape exits manage mode and clears the selection', (
    tester,
  ) async {
    await withApp(tester, () async {
      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      await tester.tap(card('b1'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 本'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 本'), findsNothing);

      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 本'), findsOneWidget);
    });
  });
}
