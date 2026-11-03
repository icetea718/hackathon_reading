import 'package:drift/drift.dart';

import '../../domain/models/annotation.dart';
import '../db/app_database.dart';

class AnnotationRepository {
  AnnotationRepository(this._db);

  final AppDatabase _db;

  Future<List<Annotation>> getForBook(
    String bookId, {
    AnnotationType? type,
  }) async {
    final query = _db.select(_db.annotations)
      ..where((t) => t.bookId.equals(bookId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.anchorStart),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    if (type != null) {
      query.where((t) => t.type.equals(type.name));
    }
    final rows = await query.get();
    return rows.map(_toAnnotation).toList();
  }

  Future<void> upsert(Annotation annotation) async {
    await _db
        .into(_db.annotations)
        .insertOnConflictUpdate(_toCompanion(annotation));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.annotations)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteForBook(String bookId) async {
    await (_db.delete(_db.annotations)..where((t) => t.bookId.equals(bookId)))
        .go();
  }

  Annotation _toAnnotation(AnnotationRecord row) {
    return Annotation(
      id: row.id,
      bookId: row.bookId,
      chapterId: row.chapterId,
      type: AnnotationType.fromName(row.type),
      anchorStart: row.anchorStart,
      anchorEnd: row.anchorEnd,
      selectedText: row.selectedText,
      color: row.color,
      noteText: row.noteText,
      anchorVersion: row.anchorVersion,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  AnnotationsCompanion _toCompanion(Annotation annotation) {
    return AnnotationsCompanion.insert(
      id: annotation.id,
      bookId: annotation.bookId,
      chapterId: Value(annotation.chapterId),
      type: annotation.type.name,
      anchorStart: annotation.anchorStart,
      anchorEnd: Value(annotation.anchorEnd),
      selectedText: Value(annotation.selectedText),
      color: Value(annotation.color),
      noteText: Value(annotation.noteText),
      anchorVersion: Value(annotation.anchorVersion),
      createdAt: annotation.createdAt,
      updatedAt: annotation.updatedAt,
    );
  }
}
