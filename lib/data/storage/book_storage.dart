import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/book.dart';
import '../../domain/models/book_illustration.dart';
import '../../domain/models/comic_page.dart';

class BookStorage {
  BookStorage(this.booksRoot);

  final Directory booksRoot;

  Future<String> copyIn(
    String sourcePath,
    String id,
    BookFormat format,
  ) async {
    await booksRoot.create(recursive: true);
    final target = p.join(booksRoot.path, '$id.${format.extension}');
    final copied = await File(sourcePath).copy(target);
    return copied.path;
  }

  Future<String> saveCover(
    List<int> bytes,
    String id,
    String extension,
  ) async {
    final covers = Directory(p.join(booksRoot.path, 'covers'));
    await covers.create(recursive: true);
    final target = File(p.join(covers.path, '$id.$extension'));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Directory comicDir(String id) => Directory(p.join(booksRoot.path, 'comic', id));

  Future<void> saveComicPages(
    String id,
    List<({List<int> bytes, String extension, String? title})> pages,
  ) async {
    final dir = comicDir(id);
    await dir.create(recursive: true);
    final titles = <String?>[];
    for (var i = 0; i < pages.length; i++) {
      final name = (i + 1).toString().padLeft(4, '0');
      final target = File(p.join(dir.path, '$name.${pages[i].extension}'));
      await target.writeAsBytes(pages[i].bytes, flush: true);
      titles.add(pages[i].title);
    }
    await File(p.join(dir.path, 'titles.json'))
        .writeAsString(jsonEncode(titles), flush: true);
  }

  Future<List<ComicPage>> loadComicPages(String id) async {
    final dir = comicDir(id);
    if (!await dir.exists()) return const [];

    final titles = await _readComicTitles(dir);
    final files = await dir
        .list()
        .where((entity) => entity is File && _isRasterPage(entity.path))
        .cast<File>()
        .toList();
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    return [
      for (var i = 0; i < files.length; i++)
        ComicPage(
          path: files[i].path,
          title: i < titles.length ? titles[i] : null,
        ),
    ];
  }

  Future<void> deleteComicPages(String id) async {
    final dir = comicDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<List<String?>> _readComicTitles(Directory dir) async {
    final file = File(p.join(dir.path, 'titles.json'));
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded.map((title) => title is String ? title : null).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Directory illustrationsDir(String id) =>
      Directory(p.join(booksRoot.path, 'illustrations', id));

  Future<void> saveIllustrations(
    String id,
    List<
            ({
              int chapterIndex,
              int offset,
              int width,
              int height,
              List<int> bytes,
              String extension,
            })>
        images,
  ) async {
    await deleteIllustrations(id);
    final dir = illustrationsDir(id);
    await dir.create(recursive: true);

    final named = <String, String>{};
    final entries = <Map<String, Object>>[];
    for (final image in images) {
      final hash = sha256.convert(image.bytes).toString();
      var name = named[hash];
      if (name == null) {
        final extension = image.extension.toLowerCase();
        name = '${(named.length + 1).toString().padLeft(4, '0')}.$extension';
        await File(p.join(dir.path, name))
            .writeAsBytes(image.bytes, flush: true);
        named[hash] = name;
      }
      entries.add({
        'file': name,
        'chapter': image.chapterIndex,
        'offset': image.offset,
        'width': image.width,
        'height': image.height,
      });
    }

    await File(p.join(dir.path, 'index.json')).writeAsString(
      jsonEncode({'version': 1, 'images': entries}),
      flush: true,
    );
  }

  /// Returns null when there is no usable manifest, and an empty list when
  /// the book was checked and has no illustrations.
  Future<List<BookIllustration>?> loadIllustrations(String id) async {
    final dir = illustrationsDir(id);
    final index = File(p.join(dir.path, 'index.json'));
    if (!await index.exists()) return null;
    try {
      final decoded = jsonDecode(await index.readAsString());
      if (decoded is! Map || decoded['version'] != 1) return null;
      final images = decoded['images'];
      if (images is! List) return null;
      final result = <BookIllustration>[];
      for (final entry in images) {
        if (entry is! Map) continue;
        final file = entry['file'];
        final chapter = entry['chapter'];
        final offset = entry['offset'];
        final width = entry['width'];
        final height = entry['height'];
        if (file is! String ||
            chapter is! int ||
            offset is! int ||
            width is! int ||
            height is! int) {
          continue;
        }
        final path = p.join(dir.path, file);
        if (!await File(path).exists()) continue;
        result.add(BookIllustration(
          path: path,
          chapterIndex: chapter,
          offset: offset,
          width: width,
          height: height,
        ));
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteIllustrations(String id) async {
    final dir = illustrationsDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<bool> hasIllustrationIndex(String id) =>
      File(p.join(illustrationsDir(id).path, 'index.json')).exists();
}

bool _isRasterPage(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  return _rasterExtensions.contains(extension);
}

const _rasterExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
