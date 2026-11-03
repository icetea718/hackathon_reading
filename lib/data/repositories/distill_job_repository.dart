import 'package:drift/drift.dart';

import '../../domain/models/distill.dart';
import '../db/app_database.dart';

class DistillJobRepository {
  DistillJobRepository(this._db);

  final AppDatabase _db;

  Future<DistillJob?> getByBook(String bookId) async {
    final query = _db.select(_db.distillJobs)
      ..where((t) => t.bookId.equals(bookId))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<void> save(DistillJob job) async {
    await _db.into(_db.distillJobs).insertOnConflictUpdate(
          DistillJobsCompanion.insert(
            id: job.id,
            bookId: job.bookId,
            contentHash: job.contentHash,
            status: job.status.name,
            stage: job.stage.name,
            pipelineVersion: job.pipelineVersion,
            totalUnits: Value(job.totalUnits),
            doneUnits: Value(job.doneUnits),
            errorText: Value(job.errorText),
            createdAt: job.createdAt,
            updatedAt: job.updatedAt,
          ),
        );
  }

  Future<void> deleteForBook(String bookId) async {
    await (_db.delete(_db.distillJobs)
          ..where((t) => t.bookId.equals(bookId)))
        .go();
  }

  DistillJob _toModel(DistillJobRow row) {
    return DistillJob(
      id: row.id,
      bookId: row.bookId,
      contentHash: row.contentHash,
      status: DistillStatus.values.byName(row.status),
      stage: DistillStage.values.byName(row.stage),
      pipelineVersion: row.pipelineVersion,
      totalUnits: row.totalUnits,
      doneUnits: row.doneUnits,
      errorText: row.errorText,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
