import 'dart:io';

import 'package:crypto/crypto.dart';

import '../data/repositories/book_repository.dart';
import '../data/repositories/distill_artifact_repository.dart';
import '../domain/models/book.dart';

/// Outcome of comparing a stored book hash with the file on disk.
class StaleCheck {
  const StaleCheck({required this.changed, this.hash});

  /// True when the file no longer matches the hash it was distilled with.
  final bool changed;

  /// Fresh hash of the file, or null when the file could not be read.
  final String? hash;
}

/// Re-hashes book files before a distillation run so old artifacts do not
/// silently describe text the reader can no longer see.
class DistillStaleGuard {
  const DistillStaleGuard({required this.books, required this.artifacts});

  final BookRepository books;
  final DistillArtifactRepository artifacts;

  Future<StaleCheck> ensureFresh(Book book) async {
    final hash = await _fileHash(book.sourcePath);
    if (hash == null || hash == book.contentHash) {
      return StaleCheck(changed: false, hash: hash);
    }
    await artifacts.markStale(book.id);
    await books.upsert(
      Book(
        id: book.id,
        title: book.title,
        author: book.author,
        format: book.format,
        sourcePath: book.sourcePath,
        addedAt: book.addedAt,
        coverPath: book.coverPath,
        contentHash: hash,
        lastOpenedAt: book.lastOpenedAt,
      ),
    );
    // A book imported before hashing existed has no baseline to be stale
    // against; only an actual change counts.
    return StaleCheck(changed: book.contentHash != null, hash: hash);
  }

  Future<String?> _fileHash(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return (await sha256.bind(file.openRead()).first).toString();
    } on FileSystemException {
      return null;
    }
  }
}
