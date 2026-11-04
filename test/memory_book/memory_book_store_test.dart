import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/memory_book/memory_book_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late MemoryBookStore store;
  late File source;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memory_book_store_test');
    store = MemoryBookStore(Directory(p.join(temp.path, 'memory_books')));
    await store.init();
    source = File(p.join(temp.path, 'source.png'));
    await source.writeAsBytes(const [1, 2, 3, 4]);
  });

  tearDown(() async {
    await store.dispose();
    await temp.delete(recursive: true);
  });

  test('creates books/pages, renames and moves a page', () async {
    final book = await store.createBook('雪夜站台');
    expect(book.title, '雪夜站台');
    expect(book.pageCount, 0);

    final page = await store.addPage(
      bookId: book.id,
      sourcePath: source.path,
      excerpt: '雪停了。她站在站台上，火车缓缓开走。',
      medium: '水彩',
    );
    expect(File(page.imagePath).existsSync(), isTrue);

    final loaded = (await store.load()).single;
    expect(loaded.pageCount, 1);
    expect(loaded.pages.single.medium, '水彩');

    await store.renameBook(book.id, '雪夜');
    expect((await store.load()).single.title, '雪夜');

    final other = await store.createBook('另一本');
    await store.movePage(
      fromBookId: book.id,
      pageId: page.id,
      toBookId: other.id,
    );

    final books = await store.load();
    final sourceBook = books.firstWhere((item) => item.id == book.id);
    final targetBook = books.firstWhere((item) => item.id == other.id);
    expect(sourceBook.pageCount, 0);
    expect(targetBook.pageCount, 1);
    expect(File(targetBook.pages.single.imagePath).existsSync(), isTrue);
  });

  test('truncates long excerpts to 60 chars plus an ellipsis', () async {
    final book = await store.createBook('长文');
    final page = await store.addPage(
      bookId: book.id,
      sourcePath: source.path,
      excerpt: '字' * 100,
    );
    expect(page.excerpt.length, 61);
    expect(page.excerpt.endsWith('…'), isTrue);
  });

  test('deletes a page and a book with its files', () async {
    final book = await store.createBook('要删除的');
    final page = await store.addPage(
      bookId: book.id,
      sourcePath: source.path,
    );
    await store.deletePage(book.id, page.id);
    expect((await store.load()).single.pageCount, 0);
    expect(File(page.imagePath).existsSync(), isFalse);

    await store.addPage(bookId: book.id, sourcePath: source.path);
    final bookDir = Directory(p.join(store.root.path, book.id));
    expect(await bookDir.exists(), isTrue);

    await store.deleteBook(book.id);
    expect(await store.load(), isEmpty);
    expect(await bookDir.exists(), isFalse);
  });
}
