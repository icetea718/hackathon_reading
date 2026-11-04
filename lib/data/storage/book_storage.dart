import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/book.dart';
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
}

bool _isRasterPage(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  return _rasterExtensions.contains(extension);
}

const _rasterExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
