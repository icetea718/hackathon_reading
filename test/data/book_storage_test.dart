import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late BookStorage storage;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('book_storage_test');
    storage = BookStorage(Directory(p.join(temp.path, 'books')));
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('saves comic pages in order with their titles and deletes them',
      () async {
    await storage.saveComicPages('b1', const [
      (bytes: [1, 2], extension: 'jpg', title: '第一话'),
      (bytes: [3], extension: 'png', title: null),
    ]);

    final pages = await storage.loadComicPages('b1');

    expect(pages, hasLength(2));
    expect(File(pages[0].path).readAsBytesSync(), [1, 2]);
    expect(File(pages[1].path).readAsBytesSync(), [3]);
    expect(pages.map((page) => page.title), ['第一话', null]);

    await storage.deleteComicPages('b1');
    expect(await storage.loadComicPages('b1'), isEmpty);
  });

  test('returns an empty list when the book has no comic pages', () async {
    expect(await storage.loadComicPages('missing'), isEmpty);
  });
}
