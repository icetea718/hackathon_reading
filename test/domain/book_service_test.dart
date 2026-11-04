import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/annotation_repository.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/category_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/data/repositories/progress_repository.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/domain/models/annotation.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/services/book_service.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late BookRepository repo;
  late BookService service;
  var nextId = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('book_service_test');
    db = AppDatabase(NativeDatabase.memory());
    repo = BookRepository(db);
    nextId = 0;
    service = BookService(
      books: repo,
      chapters: ChapterRepository(db),
      progress: ProgressRepository(db),
      annotations: AnnotationRepository(db),
      storage: BookStorage(Directory('${temp.path}/books')),
      newId: () => 'id-${nextId++}',
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('imports an uppercase TXT with a Chinese name', () async {
    final source = File('${temp.path}/我的 小说.TXT')
      ..writeAsStringSync('第一章 开始\n内容');
    final book = await service.importFile(source.path);
    expect(book.format, BookFormat.txt);
    expect(book.title, '我的 小说');
    expect(File(book.sourcePath).readAsStringSync(), contains('第一章'));
    expect((await repo.getAll()).single.id, book.id);
    expect(book.sourcePath, endsWith('${book.id}.txt'));
  });

  test('rejects unsupported extensions without recording a book', () async {
    final source = File('${temp.path}/a.doc')..writeAsStringSync('x');
    await expectLater(service.importFile(source.path),
        throwsA(isA<UnsupportedBookFormatException>()));
    expect(await repo.getAll(), isEmpty);
  });

  test('rejects empty files without recording a book', () async {
    final source = File('${temp.path}/empty.txt')..writeAsBytesSync([]);
    await expectLater(service.importFile(source.path),
        throwsA(isA<EmptyBookException>()));
    expect(await repo.getAll(), isEmpty);
  });

  test('delete removes the copied file and the record', () async {
    final source = File('${temp.path}/t.txt')..writeAsStringSync('x');
    final book = await service.importFile(source.path);
    expect(File(book.sourcePath).existsSync(), isTrue);
    await service.deleteBook(book);
    expect(File(book.sourcePath).existsSync(), isFalse);
    expect(await repo.getAll(), isEmpty);
  });

  test('rejects importing the same file twice', () async {
    final source = File('${temp.path}/same.txt')
      ..writeAsStringSync('第一章 开始\n内容');
    final first = await service.importFile(source.path);

    await expectLater(
      service.importFile(source.path),
      throwsA(isA<DuplicateBookException>()),
    );

    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.single.id, first.id);
    expect(Directory('${temp.path}/books').listSync(), hasLength(1));
  });

  test('backfills hashes for books imported before deduplication', () async {
    final source = File('${temp.path}/legacy.txt')
      ..writeAsStringSync('旧书内容');
    final book = await service.importFile(source.path);
    await repo.upsert(Book(
      id: book.id,
      title: book.title,
      author: book.author,
      format: book.format,
      sourcePath: book.sourcePath,
      addedAt: book.addedAt,
    ));
    expect((await repo.getById(book.id))!.contentHash, isNull);

    await service.backfillContentHashes();

    expect((await repo.getById(book.id))!.contentHash, isNotNull);
    await expectLater(
      service.importFile(source.path),
      throwsA(isA<DuplicateBookException>()),
    );
  });

  test('does not treat different files as duplicates', () async {
    final one = File('${temp.path}/one.txt')
      ..writeAsStringSync('第一章 开始\n内容一');
    final two = File('${temp.path}/two.txt')
      ..writeAsStringSync('第一章 开始\n内容二');

    await service.importFile(one.path);
    await service.importFile(two.path);

    expect(await repo.getAll(), hasLength(2));
  });

  test('delete removes annotations for the book', () async {
    final source = File('${temp.path}/t.txt')..writeAsStringSync('x');
    final book = await service.importFile(source.path);
    final annotations = AnnotationRepository(db);
    await annotations.upsert(Annotation(
      id: 'a1',
      bookId: book.id,
      type: AnnotationType.bookmark,
      anchorStart: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    await service.deleteBook(book);
    expect(await annotations.getForBook(book.id), isEmpty);
  });

  test('deleting a book removes its category memberships', () async {
    final categories = CategoryRepository(db);
    final category = await categories.create('科幻');
    await repo.upsert(Book(
      id: 'b1',
      title: '书',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/b1.txt',
      addedAt: DateTime(2026, 1, 1),
    ));
    await categories.addBook('b1', category.id);
    final service = BookService(
      books: repo,
      chapters: ChapterRepository(db),
      progress: ProgressRepository(db),
      annotations: AnnotationRepository(db),
      storage: BookStorage(Directory('${temp.path}/books')),
      categories: categories,
    );

    await service.deleteBook((await repo.getById('b1'))!);

    expect(await categories.watchMemberships().first, isEmpty);
  });
}
