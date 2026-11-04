import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/features/companion/companion_memory_sheet.dart';
import 'package:hackathon_reading/features/illustration/illustration_composer_page.dart';
import 'package:hackathon_reading/features/memory_book/memory_book_page.dart';
import 'package:hackathon_reading/features/memory_book/memory_book_providers.dart';
import 'package:hackathon_reading/memory_book/memory_book_models.dart';
import 'package:hackathon_reading/memory_book/memory_book_store.dart';

class _FakeStore extends MemoryBookStore {
  _FakeStore() : super(Directory.systemTemp);

  final List<String> created = [];

  @override
  Future<MemoryBook> createBook(String title) async {
    created.add(title);
    final now = DateTime(2026, 11, 4);
    return MemoryBook(
      id: 'new-book',
      title: title,
      createdAt: now,
      updatedAt: now,
      pages: const [],
    );
  }
}

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  final now = DateTime(2026, 11, 4);

  MemoryBook book(String id, String title) => MemoryBook(
        id: id,
        title: title,
        createdAt: now,
        updatedAt: now,
        pages: const [],
      );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required Stream<List<MemoryBook>> books,
    MemoryBookStore? store,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          memoryBookListProvider.overrideWith((ref) => books),
          if (store != null)
            memoryBookStoreProvider.overrideWith((ref) async => store),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const CompanionMemorySheet(
                    initialText: '这一页的正文。',
                    contextLabel: '活着 · 第一章',
                  ),
                ),
                child: const Text('打开回忆录'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开回忆录'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet offers both entries and lists the books',
      (tester) async {
    await pumpSheet(tester, books: Stream.value([book('book-1', '雪夜站台')]));

    expect(find.byKey(const Key('companion-memory-sheet')), findsOneWidget);
    expect(find.text('把这一页画成插画'), findsOneWidget);
    expect(find.text('新建回忆录…'), findsOneWidget);
    expect(find.byKey(const Key('companion-memory-book-book-1')),
        findsOneWidget);
    expect(find.text('雪夜站台'), findsOneWidget);
  });

  testWidgets('generating carries the current page text into the composer',
      (tester) async {
    await pumpSheet(tester, books: Stream.value(const []));

    await tester.tap(find.byKey(const Key('companion-memory-generate')));
    await tester.pumpAndSettle();

    expect(find.byType(IllustrationComposerPage), findsOneWidget);
    expect(find.text('这一页的正文。'), findsOneWidget);
    expect(find.text('活着 · 第一章'), findsOneWidget);
  });

  testWidgets('tapping a book opens it', (tester) async {
    await pumpSheet(tester, books: Stream.value([book('book-1', '雪夜站台')]));

    await tester.tap(find.byKey(const Key('companion-memory-book-book-1')));
    await tester.pumpAndSettle();

    expect(find.byType(MemoryBookPage), findsOneWidget);
    expect(find.text('雪夜站台'), findsWidgets);
  });

  testWidgets('a new memory book can be created and opened from the sheet',
      (tester) async {
    final store = _FakeStore();
    final books = StreamController<List<MemoryBook>>();
    addTearDown(books.close);
    books.add(const []);
    await pumpSheet(tester, books: books.stream, store: store);

    await tester.tap(find.byKey(const Key('companion-memory-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '雪夜站台');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(store.created, ['雪夜站台']);
    expect(find.byType(MemoryBookPage), findsOneWidget);

    books.add([book('new-book', '雪夜站台')]);
    await tester.pumpAndSettle();

    expect(find.text('雪夜站台'), findsWidgets);
  });
}
