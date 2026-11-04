import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/repositories/annotation_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/repositories/category_repository.dart';
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
    this.categories,
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
  final CategoryRepository? categories;
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
    var book = Book(
      id: id,
      title: p.basenameWithoutExtension(sourcePath),
      author: '',
      format: format,
      sourcePath: copiedPath,
      contentHash: contentHash,
      addedAt: DateTime.now(),
    );
    String? coverPath;

    try {
      await books.upsert(book);
      if (format == BookFormat.txt) {
        final bytes = await File(copiedPath).readAsBytes();
        final document = parseTxtDocument(bytes, fallbackTitle: book.title);
        await chapters.replaceForBook(id, _toChapters(book, document));
      } else if (format == BookFormat.epub) {
        final bytes = await File(copiedPath).readAsBytes();
        final document = parseEpubDocument(bytes);
        var cover = document.cover;

        if (document.fixedLayout || document.chapters.isEmpty) {
          final comic = parseEpubComic(bytes);
          if (comic != null) {
            await storage.saveComicPages(
              id,
              [
                for (final page in comic.pages)
                  (
                    bytes: page.bytes,
                    extension: page.extension,
                    title: page.title,
                  ),
              ],
            );
            book = _asComic(book);
            await books.upsert(book);
            cover ??= EpubCover(
              bytes: comic.pages.first.bytes,
              extension: comic.pages.first.extension,
            );
          }
        }

        if (book.comic) {
          await chapters.replaceForBook(id, const []);
        } else {
          if (document.chapters.isEmpty) {
            throw EpubParseException('没有可读正文');
          }
          await chapters.replaceForBook(id, _toEpubChapters(book, document));
        }

        if (cover != null) {
          try {
            coverPath = await storage.saveCover(
              cover.bytes,
              id,
              cover.extension,
            );
            book = _withCover(book, coverPath);
            await books.upsert(book);
          } catch (_) {
            // A cover is decorative; keep the book when it cannot be saved.
            coverPath = null;
          }
        }
      }
    } catch (_) {
      await chapters.replaceForBook(id, const []);
      await storage.deleteComicPages(id);
      await books.delete(id);
      await storage.deleteFile(copiedPath);
      if (coverPath != null) await storage.deleteFile(coverPath);
      rethrow;
    }
    return book;
  }

  final Set<String> _coverChecked = {};

  Future<void> backfillCovers() async {
    for (final book in await books.getAll()) {
      if (book.format != BookFormat.epub || book.coverPath != null) continue;
      if (!_coverChecked.add(book.id)) continue;
      try {
        final file = File(book.sourcePath);
        if (!await file.exists()) continue;
        final cover = parseEpubCover(await file.readAsBytes());
        if (cover == null) continue;
        final coverPath = await storage.saveCover(
          cover.bytes,
          book.id,
          cover.extension,
        );
        await books.upsert(_withCover(book, coverPath));
      } catch (_) {
        // Unreadable or coverless EPUBs keep the default cover.
      }
    }
  }

  Book _withCover(Book book, String coverPath) {
    return Book(
      id: book.id,
      title: book.title,
      author: book.author,
      format: book.format,
      sourcePath: book.sourcePath,
      coverPath: coverPath,
      contentHash: book.contentHash,
      comic: book.comic,
      addedAt: book.addedAt,
      lastOpenedAt: book.lastOpenedAt,
    );
  }

  Book _asComic(Book book) {
    return Book(
      id: book.id,
      title: book.title,
      author: book.author,
      format: book.format,
      sourcePath: book.sourcePath,
      coverPath: book.coverPath,
      contentHash: book.contentHash,
      comic: true,
      addedAt: book.addedAt,
      lastOpenedAt: book.lastOpenedAt,
    );
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
          comic: book.comic,
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
    await categories?.deleteForBook(book.id);
    await books.delete(book.id);
    await storage.deleteComicPages(book.id);
    await storage.deleteFile(book.sourcePath);
    if (book.coverPath != null) await storage.deleteFile(book.coverPath!);
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
