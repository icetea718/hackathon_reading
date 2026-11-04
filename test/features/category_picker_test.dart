import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/category_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/features/library/category_dialogs.dart';

Book book(String id) => Book(
  id: id,
  title: '书$id',
  author: '',
  format: BookFormat.txt,
  sourcePath: 'C:/books/$id.txt',
  addedAt: DateTime(2026, 1, 1),
);

class Harness extends StatelessWidget {
  const Harness({super.key, required this.bookIds});

  final Set<String> bookIds;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('open-picker'),
          onPressed: () =>
              showCategoryPickerDialog(context, bookIds: bookIds),
          child: const Text('打开'),
        ),
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    final books = BookRepository(db);
    await books.upsert(book('b1'));
    await books.upsert(book('b2'));
    await books.upsert(book('b3'));
  });

  tearDown(() => db.close());

  Future<T> io<T>(WidgetTester tester, Future<T> Function() action) async {
    final result = await tester.runAsync(action);
    return result as T;
  }

  Future<void> openPicker(WidgetTester tester, Set<String> bookIds) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: Harness(bookIds: bookIds)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
  }

  /// Unmounts the dialog and flushes Drift's stream-cancel timer so the test
  /// does not trip the pending-timer check at teardown.
  Future<void> disposePicker(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> runPickerTest(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } finally {
      await disposePicker(tester);
    }
  }

  Future<List<BookCategoryRecord>> memberships(WidgetTester tester) {
    return io(tester, () => db.select(db.bookCategories).get());
  }

  /// Taps [finder], then alternates real-zone time with frame pumping.
  ///
  /// Drift notifies query streams on timers owned by the zone the write ran
  /// in; once the first insert notifies, its stream re-query holds the
  /// executor until the fake clock advances. A single long runAsync therefore
  /// stalls the remaining inserts, so each round pumps frames before the next
  /// real-time slice.
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

  testWidgets('toggling a category adds and removes one book', (tester) async {
    await runPickerTest(tester, () async {
      final sciFi = await io(tester, () => categories.create('科幻'));
      await openPicker(tester, {'b1'});
      final checkbox = find.byKey(Key('picker-checkbox-${sciFi.id}'));

      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tapAndSettle(tester, checkbox);
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(await memberships(tester), hasLength(1));

      await tapAndSettle(tester, checkbox);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(await memberships(tester), isEmpty);
    });
  });

  testWidgets('bulk selection cycles through partial, all, and none', (
    tester,
  ) async {
    await runPickerTest(tester, () async {
      final sciFi = await io(tester, () => categories.create('科幻'));
      await io(tester, () => categories.addBook('b1', sciFi.id));
      await openPicker(tester, {'b1', 'b2', 'b3'});
      final checkbox = find.byKey(Key('picker-checkbox-${sciFi.id}'));

      expect(tester.widget<Checkbox>(checkbox).value, isNull);
      await tapAndSettle(tester, checkbox);
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(await memberships(tester), hasLength(3));

      await tapAndSettle(tester, checkbox);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(await memberships(tester), isEmpty);
    });
  });

  testWidgets('creating a category adds every selected book', (tester) async {
    await runPickerTest(tester, () async {
      await openPicker(tester, {'b1', 'b2'});

      await tester.tap(find.byKey(const Key('category-picker-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category-name-field')),
        '文学',
      );
      await tester.pump();
      await tapAndSettle(
        tester,
        find.byKey(const Key('category-name-confirm')),
      );

      final all = await io(tester, categories.getAll);
      expect(all.single.name, '文学');
      final rows = await memberships(tester);
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.bookId).toSet(), {'b1', 'b2'});
    });
  });

  testWidgets('done closes the picker', (tester) async {
    await runPickerTest(tester, () async {
      await io(tester, () => categories.create('科幻'));
      await openPicker(tester, {'b1'});

      expect(find.text('添加到分类'), findsOneWidget);
      await tester.tap(find.byKey(const Key('category-picker-done')));
      await tester.pumpAndSettle();

      expect(find.text('添加到分类'), findsNothing);
    });
  });

  testWidgets('picker lists every category with tri-state checkboxes', (
    tester,
  ) async {
    await runPickerTest(tester, () async {
      final sciFi = await io(tester, () => categories.create('科幻'));
      final history = await io(tester, () => categories.create('历史'));
      await openPicker(tester, {'b1'});

      expect(find.byKey(Key('picker-checkbox-${sciFi.id}')), findsOneWidget);
      expect(find.byKey(Key('picker-checkbox-${history.id}')), findsOneWidget);
      expect(find.text('科幻'), findsOneWidget);
      expect(find.text('历史'), findsOneWidget);
    });
  });
}
