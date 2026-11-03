import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/repositories/book_repository.dart';
import '../../data/storage/book_storage.dart';
import '../models/book.dart';

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
    required this.storage,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;

  final BookRepository books;
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
    } catch (_) {
      await storage.deleteFile(copiedPath);
      rethrow;
    }
    return book;
  }

  Future<void> deleteBook(Book book) async {
    await books.delete(book.id);
    await storage.deleteFile(book.sourcePath);
  }
}
