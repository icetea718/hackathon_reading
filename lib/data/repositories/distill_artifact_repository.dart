import 'package:drift/drift.dart';

import '../../domain/models/distill.dart';
import '../db/app_database.dart';

class DistillArtifactRepository {
  DistillArtifactRepository(this._db);

  final AppDatabase _db;

  Future<void> put(DistillArtifact artifact) async {
    await _db.into(_db.distillArtifacts).insertOnConflictUpdate(
          DistillArtifactsCompanion.insert(
            id: artifact.id,
            bookId: artifact.bookId,
            kind: artifact.kind.name,
            unitKey: artifact.unitKey,
            title: artifact.title,
            body: artifact.body,
            dataJson: artifact.dataJson,
            chapterStart: Value(artifact.chapterStart),
            chapterEnd: Value(artifact.chapterEnd),
            stale: Value(artifact.stale),
            createdAt: artifact.createdAt,
          ),
        );
  }

  Future<List<DistillArtifact>> listByBook(
    String bookId, {
    DistillArtifactKind? kind,
  }) async {
    final query = _db.select(_db.distillArtifacts)
      ..where((t) => t.bookId.equals(bookId))
      ..orderBy([(t) => OrderingTerm.asc(t.unitKey)]);
    if (kind != null) {
      query.where((t) => t.kind.equals(kind.name));
    }
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  Future<void> markStale(String bookId) async {
    await (_db.update(_db.distillArtifacts)
          ..where((t) => t.bookId.equals(bookId)))
        .write(const DistillArtifactsCompanion(stale: Value(true)));
  }

  Future<void> deleteForBook(String bookId) async {
    await (_db.delete(_db.distillArtifacts)
          ..where((t) => t.bookId.equals(bookId)))
        .go();
  }

  DistillArtifact _toModel(DistillArtifactRow row) {
    return DistillArtifact(
      id: row.id,
      bookId: row.bookId,
      kind: DistillArtifactKind.values.byName(row.kind),
      unitKey: row.unitKey,
      title: row.title,
      body: row.body,
      dataJson: row.dataJson,
      chapterStart: row.chapterStart,
      chapterEnd: row.chapterEnd,
      stale: row.stale,
      createdAt: row.createdAt,
    );
  }
}
