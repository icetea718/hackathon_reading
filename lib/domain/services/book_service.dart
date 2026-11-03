import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/repositories/annotation_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/distill_artifact_repository.dart';
import '../../data/repositories/distill_job_repository.dart';
import '../../data/repositories/distill_unit_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/storage/book_storage.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import 'epub_book_parser.dart';
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

class DuplicateBookException implements Exception {
  DuplicateBookException(this.existing);

  final Book existing;

  @override
  String toString() => 'DuplicateBookException: ${existing.id}';
}

class BookService {
  BookService({
    required this.books,
    required this.chapters,
    required this.progress,
    required this.annotations,
    required this.storage,
    this.distillJobs,
    this.distillUnits,
    this.distillArtifacts,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;

  final BookRepository books;
  final ChapterRepository chapters;
  final ProgressRepository progress;
  final AnnotationRepository annotations;
  final BookStorage storage;
  final DistillJobRepository? distillJobs;
  final DistillUnitRepository? distillUnits;
  final DistillArtifactRepository? distillArtifacts;
  final String Function() _newId;

  Future<Book> importFile(String sourcePath) async {
    final format = BookFormat.fromExtension(sourcePath);
    if (format == null) {
      throw UnsupportedBookFormatException(sourcePath);
    }
    final source = File(sourcePath);
    if (await source.length() == 0) {
      throw EmptyBookException(sourcePath);
    }

    final contentHash = (await sha256.bind(source.openRead()).first).toString();
    final existing = await books.getByContentHash(contentHash);
    if (existing != null) {
      throw DuplicateBookException(existing);
    }

    final id = _newId();
    final copiedPath = await storage.copyIn(sourcePath, id, format);
    final book = Book(
      id: id,
      title: p.basenameWithoutExtension(sourcePath),
      author: '',
      format: format,
      sourcePath: copiedPath,
      contentHash: contentHash,
      addedAt: DateTime.now(),
    );

    try {
      await books.upsert(book);
      if (format == BookFormat.txt) {
        final bytes = await File(copiedPath).readAsBytes();
        final document = parseTxtDocument(bytes, fallbackTitle: book.title);
        await chapters.replaceForBook(id, _toChapters(book, document));
      } else if (format == BookFormat.epub) {
        final bytes = await File(copiedPath).readAsBytes();
        final document = parseEpubDocument(bytes);
        await chapters.replaceForBook(id, _toEpubChapters(book, document));
      }
    } catch (_) {
      await chapters.replaceForBook(id, const []);
      await books.delete(id);
      await storage.deleteFile(copiedPath);
      rethrow;
    }
    return book;
  }

  Future<void> backfillContentHashes() async {
    for (final book in await books.getAll()) {
      if (book.contentHash != null) continue;
      try {
        final file = File(book.sourcePath);
        if (!await file.exists()) continue;
        final hash = (await sha256.bind(file.openRead()).first).toString();
        await books.upsert(Book(
          id: book.id,
          title: book.title,
          author: book.author,
          format: book.format,
          sourcePath: book.sourcePath,
          coverPath: book.coverPath,
          contentHash: hash,
          addedAt: book.addedAt,
          lastOpenedAt: book.lastOpenedAt,
        ));
      } catch (_) {
        // Missing or unreadable files simply stay out of deduplication.
      }
    }
  }

  Future<void> deleteBook(Book book) async {
    await chapters.replaceForBook(book.id, const []);
    await progress.delete(book.id);
    await annotations.deleteForBook(book.id);
    await distillUnits?.deleteForBook(book.id);
    await distillArtifacts?.deleteForBook(book.id);
    await distillJobs?.deleteForBook(book.id);
    await books.delete(book.id);
    await storage.deleteFile(book.sourcePath);
  }

  List<Chapter> _toEpubChapters(Book book, EpubDocument document) {
    return [
      for (var i = 0; i < document.chapters.length; i++)
        Chapter(
          id: '${book.id}-c$i',
          bookId: book.id,
          index: i,
          title: document.chapters[i].title,
          startOffset: document.chapters[i].startOffset,
          endOffset: document.chapters[i].endOffset,
          contentText: document.chapters[i].contentText,
        ),
    ];
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
