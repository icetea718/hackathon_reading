import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/features/reader/reader_providers.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late BookStorage storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('illustration_provider');
    db = AppDatabase(NativeDatabase.memory());
    storage = BookStorage(Directory('${temp.path}/books'));
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<ReaderData> read(String bookId) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        bookStorageProvider.overrideWith((ref) async => storage),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(readerDataProvider(bookId), (_, _) {});
    addTearDown(sub.close);
    return container.read(readerDataProvider(bookId).future);
  }

  test('epub reader data carries the saved illustrations', () async {
    await BookRepository(db).upsert(Book(
      id: 'b1',
      title: '插图本',
      author: '',
      format: BookFormat.epub,
      sourcePath: 'C:/books/missing.epub',
      addedAt: DateTime(2026, 1, 1),
    ));
    await ChapterRepository(db).replaceForBook('b1', [
      const Chapter(
        id: 'b1-c0',
        bookId: 'b1',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: 4,
        contentText: '正文',
      ),
    ]);
    await storage.saveIllustrations('b1', const [
      (
        chapterIndex: 0,
        offset: 2,
        width: 100,
        height: 50,
        bytes: [1],
        extension: 'png'
      ),
    ]);

    final data = await read('b1');
    expect(data.illustrations, hasLength(1));
    expect(data.illustrations.single.offset, 2);
  });

  test('txt books and missing books have no illustrations', () async {
    await BookRepository(db).upsert(Book(
      id: 't1',
      title: '文本',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/t.txt',
      addedAt: DateTime(2026, 1, 1),
    ));

    expect((await read('t1')).illustrations, isEmpty);
    expect((await read('missing')).illustrations, isEmpty);
  });
}
