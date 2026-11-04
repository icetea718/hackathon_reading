import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'memory_book_models.dart';

/// 回忆录的本地存储：一个 JSON 索引 + 每本一个图片目录。
///
/// 使用 JSON 而不是改 drift 表，避免动数据库 schema 和生成代码；
/// 对“用户自建、多本、可删页/移页”的需求已经够用。
class MemoryBookStore {
  MemoryBookStore(this.root);

  final Directory root;
  final StreamController<List<MemoryBook>> _changes =
      StreamController<List<MemoryBook>>.broadcast();

  File get _indexFile => File(p.join(root.path, 'index.json'));

  Future<void> init() async {
    await root.create(recursive: true);
  }

  Future<List<MemoryBook>> load() async {
    if (!await _indexFile.exists()) return [];
    try {
      final decoded = jsonDecode(await _indexFile.readAsString());
      if (decoded is! Map) return [];
      final rawBooks = decoded['books'];
      if (rawBooks is! List) return [];
      final books = <MemoryBook>[];
      for (final raw in rawBooks) {
        if (raw is! Map) continue;
        final id = raw['id'];
        final title = raw['title'];
        if (id is! String || title is! String) continue;
        final createdAt =
            DateTime.tryParse(raw['createdAt']?.toString() ?? '') ??
                DateTime.now();
        final updatedAt =
            DateTime.tryParse(raw['updatedAt']?.toString() ?? '') ??
                createdAt;
        final pages = <MemoryPage>[];
        final rawPages = raw['pages'];
        if (rawPages is List) {
          for (final rawPage in rawPages) {
            if (rawPage is! Map) continue;
            final pageId = rawPage['id'];
            final fileName = rawPage['fileName'];
            if (pageId is! String || fileName is! String) continue;
            final pageCreatedAt =
                DateTime.tryParse(rawPage['createdAt']?.toString() ?? '') ??
                    createdAt;
            pages.add(
              MemoryPage(
                id: pageId,
                fileName: fileName,
                imagePath: p.join(root.path, id, 'pages', fileName),
                createdAt: pageCreatedAt,
                excerpt: rawPage['excerpt']?.toString() ?? '',
                medium: rawPage['medium']?.toString() ?? '',
              ),
            );
          }
        }
        books.add(
          MemoryBook(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pages: pages,
          ),
        );
      }
      books.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return books;
    } on FormatException {
      return [];
    } on FileSystemException {
      return [];
    }
  }

  Stream<List<MemoryBook>> watch() async* {
    yield await load();
    yield* _changes.stream;
  }

  Future<MemoryBook> createBook(String title) async {
    final clean = title.trim();
    if (clean.isEmpty) {
      throw MemoryBookException('回忆录名字不能为空。');
    }
    final now = DateTime.now();
    final book = MemoryBook(
      id: const Uuid().v4(),
      title: clean,
      createdAt: now,
      updatedAt: now,
      pages: const [],
    );
    final books = await load();
    books.add(book);
    await _write(books);
    return book;
  }

  Future<void> renameBook(String bookId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) {
      throw MemoryBookException('回忆录名字不能为空。');
    }
    final books = await load();
    final index = books.indexWhere((book) => book.id == bookId);
    if (index < 0) throw MemoryBookException('找不到这本回忆录。');
    books[index] = books[index].copyWith(
      title: clean,
      updatedAt: DateTime.now(),
    );
    await _write(books);
  }

  Future<void> deleteBook(String bookId) async {
    final books = await load();
    final index = books.indexWhere((book) => book.id == bookId);
    if (index < 0) return;
    books.removeAt(index);
    final directory = Directory(p.join(root.path, bookId));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await _write(books);
  }

  Future<MemoryPage> addPage({
    required String bookId,
    required String sourcePath,
    String excerpt = '',
    String medium = '',
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw MemoryBookException('找不到要保存的图片。');
    }
    final books = await load();
    final index = books.indexWhere((book) => book.id == bookId);
    if (index < 0) throw MemoryBookException('找不到这本回忆录。');

    final book = books[index];
    final pageId = const Uuid().v4();
    final extension = p.extension(source.path).isEmpty
        ? '.png'
        : p.extension(source.path).toLowerCase();
    final fileName = '$pageId$extension';
    final pagesDir = Directory(p.join(root.path, book.id, 'pages'));
    await pagesDir.create(recursive: true);
    final target = File(p.join(pagesDir.path, fileName));
    await source.copy(target.path);

    final page = MemoryPage(
      id: pageId,
      fileName: fileName,
      imagePath: target.path,
      createdAt: DateTime.now(),
      excerpt: _trimExcerpt(excerpt),
      medium: medium.trim(),
    );
    books[index] = book.copyWith(
      pages: [...book.pages, page],
      updatedAt: DateTime.now(),
    );
    await _write(books);
    return page;
  }

  Future<void> deletePage(String bookId, String pageId) async {
    final books = await load();
    final bookIndex = books.indexWhere((book) => book.id == bookId);
    if (bookIndex < 0) return;
    final book = books[bookIndex];
    final pageIndex = book.pages.indexWhere((page) => page.id == pageId);
    if (pageIndex < 0) return;
    final page = book.pages[pageIndex];
    final file = File(page.imagePath);
    if (await file.exists()) await file.delete();
    final pages = [...book.pages]..removeAt(pageIndex);
    books[bookIndex] = book.copyWith(
      pages: pages,
      updatedAt: DateTime.now(),
    );
    await _write(books);
  }

  Future<void> movePage({
    required String fromBookId,
    required String pageId,
    required String toBookId,
  }) async {
    if (fromBookId == toBookId) return;
    final books = await load();
    final fromIndex = books.indexWhere((book) => book.id == fromBookId);
    final toIndex = books.indexWhere((book) => book.id == toBookId);
    if (fromIndex < 0 || toIndex < 0) {
      throw MemoryBookException('找不到源回忆录或目标回忆录。');
    }
    final fromBook = books[fromIndex];
    final pageIndex = fromBook.pages.indexWhere((page) => page.id == pageId);
    if (pageIndex < 0) throw MemoryBookException('找不到这张照片。');
    final page = fromBook.pages[pageIndex];

    final targetDir = Directory(p.join(root.path, toBookId, 'pages'));
    await targetDir.create(recursive: true);
    final target = File(p.join(targetDir.path, page.fileName));
    final source = File(page.imagePath);
    if (await target.exists()) await target.delete();
    if (await source.exists()) {
      await source.rename(target.path);
    }
    final movedPage = MemoryPage(
      id: page.id,
      fileName: page.fileName,
      imagePath: target.path,
      createdAt: page.createdAt,
      excerpt: page.excerpt,
      medium: page.medium,
    );

    final fromPages = [...fromBook.pages]..removeAt(pageIndex);
    final toBook = books[toIndex];
    books[fromIndex] = fromBook.copyWith(
      pages: fromPages,
      updatedAt: DateTime.now(),
    );
    books[toIndex] = toBook.copyWith(
      pages: [...toBook.pages, movedPage],
      updatedAt: DateTime.now(),
    );
    await _write(books);
  }

  Future<void> _write(List<MemoryBook> books) async {
    await root.create(recursive: true);
    final ordered = [...books]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final payload = <String, Object?>{
      'version': 1,
      'books': ordered.map((book) => book.toJson()).toList(),
    };
    final temp = File('${_indexFile.path}.tmp');
    await temp.writeAsString(jsonEncode(payload), flush: true);
    if (await _indexFile.exists()) await _indexFile.delete();
    await temp.rename(_indexFile.path);
    _changes.add(List<MemoryBook>.unmodifiable(ordered));
  }

  static String _trimExcerpt(String value) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 60) return collapsed;
    return '${collapsed.substring(0, 60).trimRight()}…';
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
