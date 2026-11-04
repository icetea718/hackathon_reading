import 'dart:io';

import 'package:chinese_codec/chinese_codec.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/annotation_repository.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/data/repositories/progress_repository.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/domain/models/reading_progress.dart';
import 'package:hackathon_reading/domain/services/book_service.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late BookRepository books;
  late ChapterRepository chapters;
  late ProgressRepository progress;
  late BookService service;
  var nextId = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('txt_import_test');
    db = AppDatabase(NativeDatabase.memory());
    books = BookRepository(db);
    chapters = ChapterRepository(db);
    progress = ProgressRepository(db);
    service = BookService(
      books: books,
      chapters: chapters,
      progress: progress,
      annotations: AnnotationRepository(db),
      storage: BookStorage(Directory('${temp.path}/books')),
      newId: () => 'id-${nextId++}',
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('UTF-8 import stores chapters in order with exact content', () async {
    const content = '前言内容\n第一章 开始\n内容一\n第二章 继续\n内容二';
    final source = File('${temp.path}/novel.txt')
      ..writeAsStringSync(content);

    final book = await service.importFile(source.path);
    final stored = await chapters.getForBook(book.id);

    expect(stored.map((c) => c.title), ['前言', '第一章 开始', '第二章 继续']);
    for (final chapter in stored) {
      expect(
        chapter.contentText,
        content.substring(chapter.startOffset, chapter.endOffset),
      );
    }
    expect(stored.first.startOffset, 0);
    expect(stored.last.endOffset, content.length);
  });

  test('TXT import stores section levels', () async {
    const content = '第一章 开始\n甲\n第一节 起\n乙\n第二章 继续\n丙';
    final source = File('${temp.path}/sections.txt')
      ..writeAsStringSync(content);

    final book = await service.importFile(source.path);
    final stored = await chapters.getForBook(book.id);

    expect(stored.map((c) => c.title), ['第一章 开始', '第一节 起', '第二章 继续']);
    expect(stored.map((c) => c.level), [1, 2, 1]);
  });

  test('GB18030 import produces the same chapter titles', () async {
    const content = '第一章 开始\n甲\n第二章 继续\n乙';
    final utf8Source = File('${temp.path}/u.txt')
      ..writeAsStringSync(content);
    final gbSource = File('${temp.path}/g.txt')
      ..writeAsBytesSync(gb18030.encode(content));

    final utf8Book = await service.importFile(utf8Source.path);
    final gbBook = await service.importFile(gbSource.path);

    final utf8Titles =
        (await chapters.getForBook(utf8Book.id)).map((c) => c.title);
    final gbTitles =
        (await chapters.getForBook(gbBook.id)).map((c) => c.title);
    expect(gbTitles, utf8Titles);
  });

  test('TXT without headings stores one chapter covering the file', () async {
    const content = '只有正文\n第二行';
    final source = File('${temp.path}/plain.txt')
      ..writeAsStringSync(content);

    final book = await service.importFile(source.path);
    final stored = await chapters.getForBook(book.id);

    expect(stored, hasLength(1));
    expect(stored.single.title, 'plain');
    expect(stored.single.startOffset, 0);
    expect(stored.single.endOffset, content.length);
    expect(stored.single.contentText, content);
  });

  test('progress save then get returns the same charOffset', () async {
    await progress.save(ReadingProgress(
      bookId: 'b1',
      anchor: const ReadingAnchor(charOffset: 42),
      percent: 0.25,
      updatedAt: DateTime(2026, 1, 1),
    ));

    final loaded = await progress.get('b1');
    expect(loaded, isNotNull);
    expect(loaded!.anchor.charOffset, 42);
    expect(loaded.percent, 0.25);
  });

  test('deleteBook removes book, chapters, progress, and copied file', () async {
    const content = '第一章 开始\n内容';
    final source = File('${temp.path}/del.txt')
      ..writeAsStringSync(content);

    final book = await service.importFile(source.path);
    await progress.save(ReadingProgress(
      bookId: book.id,
      anchor: const ReadingAnchor(charOffset: 5),
      percent: 0.5,
      updatedAt: DateTime(2026, 1, 1),
    ));
    final copied = File(book.sourcePath);
    expect(await chapters.getForBook(book.id), isNotEmpty);
    expect(copied.existsSync(), isTrue);

    await service.deleteBook(book);

    expect(await books.getAll(), isEmpty);
    expect(await chapters.getForBook(book.id), isEmpty);
    expect(await progress.get(book.id), isNull);
    expect(copied.existsSync(), isFalse);
  });
}
