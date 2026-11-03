import 'package:drift/drift.dart';

import '../../domain/models/chapter.dart';
import '../db/app_database.dart';

class ChapterRepository {
  ChapterRepository(this._db);

  final AppDatabase _db;

  Future<void> replaceForBook(String bookId, List<Chapter> chapters) async {
    await _db.transaction(() async {
      await (_db.delete(_db.chapters)
            ..where((t) => t.bookId.equals(bookId)))
          .go();
      if (chapters.isEmpty) return;
      await _db.batch((batch) {
        batch.insertAll(_db.chapters, chapters.map(_toRow).toList());
      });
    });
  }

  Future<List<Chapter>> getForBook(String bookId) async {
    final query = _db.select(_db.chapters)
      ..where((t) => t.bookId.equals(bookId))
      ..orderBy([(t) => OrderingTerm.asc(t.chapterIndex)]);
    final rows = await query.get();
    return rows.map(_toChapter).toList();
  }

  Chapter _toChapter(ChapterRecord row) {
    return Chapter(
      id: row.id,
      bookId: row.bookId,
      index: row.chapterIndex,
      title: row.title,
      startOffset: row.startOffset,
      endOffset: row.endOffset,
      contentText: row.contentText,
    );
  }

  ChaptersCompanion _toRow(Chapter chapter) {
    return ChaptersCompanion.insert(
      id: chapter.id,
      bookId: chapter.bookId,
      chapterIndex: chapter.index,
      title: chapter.title,
      startOffset: chapter.startOffset,
      endOffset: chapter.endOffset,
      contentText: chapter.contentText,
    );
  }
}
