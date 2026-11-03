import 'dart:convert';

import '../../domain/models/reading_progress.dart';
import '../db/app_database.dart';

class ProgressRepository {
  ProgressRepository(this._db);

  final AppDatabase _db;

  Future<ReadingProgress?> get(String bookId) async {
    final query = _db.select(_db.readingProgressEntries)
      ..where((t) => t.bookId.equals(bookId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return ReadingProgress(
      bookId: row.bookId,
      anchor: ReadingAnchor.fromJson(
        jsonDecode(row.anchorJson) as Map<String, dynamic>,
      ),
      percent: row.percent,
      updatedAt: row.updatedAt,
    );
  }

  Future<void> save(ReadingProgress progress) {
    return _db.into(_db.readingProgressEntries).insertOnConflictUpdate(
          ReadingProgressEntriesCompanion.insert(
            bookId: progress.bookId,
            anchorJson: jsonEncode(progress.anchor.toJson()),
            percent: progress.percent,
            updatedAt: progress.updatedAt,
          ),
        );
  }

  Future<void> delete(String bookId) {
    return (_db.delete(_db.readingProgressEntries)
          ..where((t) => t.bookId.equals(bookId)))
        .go();
  }
}
