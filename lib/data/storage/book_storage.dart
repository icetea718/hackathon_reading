import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/book.dart';

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

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
