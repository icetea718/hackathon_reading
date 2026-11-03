import 'package:drift/drift.dart';

import '../../domain/models/distill.dart';
import '../db/app_database.dart';

class DistillUnitRepository {
  DistillUnitRepository(this._db);

  final AppDatabase _db;

  Future<void> put(DistillUnit unit) async {
    await _db.into(_db.distillUnits).insertOnConflictUpdate(
          DistillUnitsCompanion.insert(
            id: unit.id,
            jobId: unit.jobId,
            unitKey: unit.unitKey,
            kind: unit.kind,
            status: unit.status,
            resultJson: Value(unit.resultJson),
            attempts: Value(unit.attempts),
            updatedAt: unit.updatedAt,
          ),
        );
  }

  Future<Set<String>> doneKeys(String jobId) async {
    final query = _db.select(_db.distillUnits)
      ..where((t) => t.jobId.equals(jobId) & t.status.equals('done'));
    final rows = await query.get();
    return rows.map((row) => row.unitKey).toSet();
  }

  Future<void> deleteForJob(String jobId) async {
    await (_db.delete(_db.distillUnits)
          ..where((t) => t.jobId.equals(jobId)))
        .go();
  }

  Future<void> deleteForBook(String bookId) async {
    final jobs = await (_db.select(_db.distillJobs)
          ..where((t) => t.bookId.equals(bookId)))
        .get();
    for (final job in jobs) {
      await deleteForJob(job.id);
    }
  }
}
