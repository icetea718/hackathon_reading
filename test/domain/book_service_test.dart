import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/services/book_service.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late BookRepository repo;
  late BookService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('book_service_test');
    db = AppDatabase(NativeDatabase.memory());
    repo = BookRepository(db);
    service = BookService(
      books: repo,
      storage: BookStorage(Directory('${temp.path}/books')),
      newId: () => 'fixed-id',
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
    expect(book.sourcePath, endsWith('fixed-id.txt'));
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
}
