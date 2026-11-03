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

  Future<List<Chapter>> getSummariesForBook(String bookId) async {
    final query = _db.selectOnly(_db.chapters)
      ..addColumns([
        _db.chapters.id,
        _db.chapters.bookId,
        _db.chapters.chapterIndex,
        _db.chapters.title,
        _db.chapters.startOffset,
        _db.chapters.endOffset,
      ])
      ..where(_db.chapters.bookId.equals(bookId))
      ..orderBy([OrderingTerm.asc(_db.chapters.chapterIndex)]);
    final rows = await query.get();
    return rows
        .map((row) => Chapter(
              id: row.read(_db.chapters.id)!,
              bookId: row.read(_db.chapters.bookId)!,
              index: row.read(_db.chapters.chapterIndex)!,
              title: row.read(_db.chapters.title)!,
              startOffset: row.read(_db.chapters.startOffset)!,
              endOffset: row.read(_db.chapters.endOffset)!,
              contentText: '',
            ))
        .toList();
  }

  Future<String?> getContent(String bookId, int chapterIndex) async {
    final query = _db.select(_db.chapters)
      ..where(
        (t) => t.bookId.equals(bookId) & t.chapterIndex.equals(chapterIndex),
      );
    final row = await query.getSingleOrNull();
    return row?.contentText;
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
