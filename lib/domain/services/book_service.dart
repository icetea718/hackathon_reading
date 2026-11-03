import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/repositories/book_repository.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/storage/book_storage.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import 'txt_book_parser.dart';

class UnsupportedBookFormatException implements Exception {
  UnsupportedBookFormatException(this.path);

  final String path;

  @override
  String toString() => 'UnsupportedBookFormatException: $path';
}

class EmptyBookException implements Exception {
  EmptyBookException(this.path);

  final String path;

  @override
  String toString() => 'EmptyBookException: $path';
}

class BookService {
  BookService({
    required this.books,
    required this.chapters,
    required this.progress,
    required this.storage,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;

  final BookRepository books;
  final ChapterRepository chapters;
  final ProgressRepository progress;
  final BookStorage storage;
  final String Function() _newId;

  Future<Book> importFile(String sourcePath) async {
    final format = BookFormat.fromExtension(sourcePath);
    if (format == null) {
      throw UnsupportedBookFormatException(sourcePath);
    }
    final length = await File(sourcePath).length();
    if (length == 0) {
      throw EmptyBookException(sourcePath);
    }

    final id = _newId();
    final copiedPath = await storage.copyIn(sourcePath, id, format);
    final book = Book(
      id: id,
      title: p.basenameWithoutExtension(sourcePath),
      author: '',
      format: format,
      sourcePath: copiedPath,
      addedAt: DateTime.now(),
    );

    try {
      await books.upsert(book);
      if (format == BookFormat.txt) {
        final bytes = await File(copiedPath).readAsBytes();
        final document = parseTxtDocument(bytes, fallbackTitle: book.title);
        await chapters.replaceForBook(id, _toChapters(book, document));
      }
    } catch (_) {
      await chapters.replaceForBook(id, const []);
      await books.delete(id);
      await storage.deleteFile(copiedPath);
      rethrow;
    }
    return book;
  }

  Future<void> deleteBook(Book book) async {
    await chapters.replaceForBook(book.id, const []);
    await progress.delete(book.id);
    await books.delete(book.id);
    await storage.deleteFile(book.sourcePath);
  }

  List<Chapter> _toChapters(Book book, TxtDocument document) {
    return [
      for (var i = 0; i < document.chapters.length; i++)
        Chapter(
          id: '${book.id}-c$i',
          bookId: book.id,
          index: i,
          title: document.chapters[i].title,
          startOffset: document.chapters[i].startOffset,
          endOffset: document.chapters[i].endOffset,
          contentText: document.text.substring(
            document.chapters[i].startOffset,
            document.chapters[i].endOffset,
          ),
        ),
    ];
  }
}
