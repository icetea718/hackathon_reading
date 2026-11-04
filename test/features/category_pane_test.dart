import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/category_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/category.dart';
import 'package:hackathon_reading/features/library/category_pane.dart';

Book book(String id) => Book(
  id: id,
  title: '书$id',
  author: '',
  format: BookFormat.txt,
  sourcePath: 'C:/books/$id.txt',
  addedAt: DateTime(2026, 1, 1),
);

void main() {
  late AppDatabase db;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    final books = BookRepository(db);
    await books.upsert(book('b1'));
    await books.upsert(book('b2'));
  });

  tearDown(() => db.close());

  Future<T> io<T>(WidgetTester tester, Future<T> Function() action) async {
    final result = await tester.runAsync(action);
    return result as T;
  }

  Future<void> flushIo(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    await tester.runAsync(() async {
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> pumpPane(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides],
        child: const MaterialApp(home: Scaffold(body: CategoryPane())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposePane(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  ListTile tileOf(WidgetTester tester, Key key) {
    return tester.widget<ListTile>(
      find.descendant(of: find.byKey(key), matching: find.byType(ListTile)),
    );
  }

  testWidgets('lists rows and counts', (tester) async {
    final category = await io(tester, () => categories.create('科幻'));
    await io(tester, () => categories.addBook('b1', category.id));
    await pumpPane(tester);

    expect(find.text('全部书籍'), findsOneWidget);
    expect(find.text('科幻'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('＋ 新建分类'), findsOneWidget);

    final row = find.byKey(Key('category-row-${category.id}'));
    expect(find.descendant(of: row, matching: find.text('1')), findsOneWidget);
    expect(tileOf(tester, const Key('category-row-all')).selected, isTrue);
    expect(
      tileOf(tester, Key('category-row-${category.id}')).selected,
      isFalse,
    );
    await disposePane(tester);
  });

  testWidgets('creates a category', (tester) async {
    await pumpPane(tester);

    await tester.tap(find.byKey(const Key('category-row-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name-field')), '科幻');
    await tester.pump();
    await flushIo(
      tester,
      () => tester.tap(find.byKey(const Key('category-name-confirm'))),
    );

    expect(find.text('科幻'), findsOneWidget);
    final all = await io(tester, categories.getAll);
    expect(all.single.name, '科幻');
    await disposePane(tester);
  });

  testWidgets('rejects duplicate names', (tester) async {
    await io(tester, () => categories.create('科幻'));
    await pumpPane(tester);

    await tester.tap(find.byKey(const Key('category-row-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name-field')),
      ' 科幻 ',
    );
    await tester.pump();
    await flushIo(
      tester,
      () => tester.tap(find.byKey(const Key('category-name-confirm'))),
    );

    expect(find.text('已有同名分类'), findsOneWidget);
    expect(find.byKey(const Key('category-name-field')), findsOneWidget);
    await disposePane(tester);
  });

  testWidgets('renames without changing the id', (tester) async {
    final category = await io(tester, () => categories.create('科幻'));
    await pumpPane(tester);
    final row = find.byKey(Key('category-row-${category.id}'));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('分类更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name-field')), '历史');
    await tester.pump();
    await flushIo(
      tester,
      () => tester.tap(find.byKey(const Key('category-name-confirm'))),
    );

    expect(find.text('历史'), findsOneWidget);
    expect(find.byKey(Key('category-row-${category.id}')), findsOneWidget);
    await disposePane(tester);
  });

  testWidgets('deletes a category without deleting books', (tester) async {
    final category = await io(tester, () => categories.create('科幻'));
    await io(tester, () => categories.addBook('b1', category.id));
    await pumpPane(tester);
    final row = find.byKey(Key('category-row-${category.id}'));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('分类更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await flushIo(
      tester,
      () => tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      ),
    );

    expect(row, findsNothing);
    expect(await io(tester, () => BookRepository(db).getAll()), hasLength(2));
    await disposePane(tester);
  });

  testWidgets('selecting a category updates the selected row', (tester) async {
    final category = await io(tester, () => categories.create('科幻'));
    await pumpPane(tester);

    await tester.tap(find.byKey(Key('category-row-${category.id}')));
    await tester.pumpAndSettle();

    expect(tileOf(tester, Key('category-row-${category.id}')).selected, isTrue);
    expect(tileOf(tester, const Key('category-row-all')).selected, isFalse);
    await disposePane(tester);
  });

  testWidgets('right-click opens the same menu', (tester) async {
    final category = await io(tester, () => categories.create('科幻'));
    await pumpPane(tester);

    await tester.tap(
      find.byKey(Key('category-row-${category.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await disposePane(tester);
  });

  testWidgets('invalid names stay in the dialog', (tester) async {
    await pumpPane(tester);

    await tester.tap(find.byKey(const Key('category-row-new')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('category-name-field')), '   ');
    await tester.pump();
    final button = tester.widget<TextButton>(
      find.byKey(const Key('category-name-confirm')),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('category-name-field')),
      'x' * 21,
    );
    await tester.pump();
    expect(find.text('名称需为 1–20 个字符'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('category-name-confirm')))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const Key('category-name-field')), '科幻');
    await tester.pump();
    expect(find.text('名称需为 1–20 个字符'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('category-name-confirm')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('category-name-field')), findsOneWidget);
    await disposePane(tester);
  });

  testWidgets('empty category list shows a hint', (tester) async {
    await pumpPane(tester);

    expect(find.text('还没有分类，可拖拽书籍到这里，或点击下方新建'), findsOneWidget);
    await disposePane(tester);
  });

  testWidgets('category load failure shows an error strip and keeps books', (
    tester,
  ) async {
    await pumpPane(
      tester,
      overrides: [
        categoriesProvider.overrideWith(
          (ref) => Stream<List<Category>>.error(StateError('boom')),
        ),
      ],
    );

    expect(find.text('分类加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('全部书籍'), findsOneWidget);
    await disposePane(tester);
  });
}
