import 'dart:convert';
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

  test('saves illustrations, dedupes bytes, and loads them back', () async {
    await storage.saveIllustrations('b1', const [
      (
        chapterIndex: 0,
        offset: 10,
        width: 800,
        height: 1200,
        bytes: [1, 2],
        extension: 'jpg'
      ),
      (
        chapterIndex: 1,
        offset: 0,
        width: 800,
        height: 1200,
        bytes: [1, 2],
        extension: 'jpg'
      ),
    ]);

    final images = await storage.loadIllustrations('b1');
    expect(images, hasLength(2));
    expect(images![0].chapterIndex, 0);
    expect(images[0].offset, 10);
    expect(images[0].width, 800);
    expect(images[1].chapterIndex, 1);
    expect(images[0].path, images[1].path);
    expect(File(images[0].path).readAsBytesSync(), [1, 2]);

    final manifest = jsonDecode(
      File(p.join(storage.illustrationsDir('b1').path, 'index.json'))
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['version'], 1);
    expect(
      (manifest['images'] as List).map((entry) => entry['file']).toList(),
      ['0001.jpg', '0001.jpg'],
    );
  });

  test('writes an empty manifest as a checked marker', () async {
    await storage.saveIllustrations('b1', const []);
    expect(await storage.loadIllustrations('b1'), isEmpty);
    expect(await storage.hasIllustrationIndex('b1'), isTrue);
    expect(await storage.loadIllustrations('other'), isNull);
  });

  test('a corrupt manifest loads as null and delete removes the directory',
      () async {
    await storage.saveIllustrations('b1', const []);
    File(p.join(storage.illustrationsDir('b1').path, 'index.json'))
        .writeAsStringSync('not json');
    expect(await storage.loadIllustrations('b1'), isNull);

    await storage.deleteIllustrations('b1');
    expect(await storage.hasIllustrationIndex('b1'), isFalse);
    expect(await storage.loadIllustrations('b1'), isNull);
  });

  test('entries whose file disappeared are skipped', () async {
    await storage.saveIllustrations('b1', const [
      (
        chapterIndex: 0,
        offset: 0,
        width: 10,
        height: 10,
        bytes: [1],
        extension: 'png'
      ),
    ]);
    final images = await storage.loadIllustrations('b1');
    File(images!.single.path).deleteSync();
    expect(await storage.loadIllustrations('b1'), isEmpty);
  });
}
