import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Books,
    Chapters,
    ReadingProgressEntries,
    Annotations,
    Settings,
    DistillJobs,
    DistillUnits,
    DistillArtifacts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.defaults() : super(driftDatabase(name: 'reader'));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(chapters);
            await m.createTable(readingProgressEntries);
          }
          if (from < 3) {
            await m.createTable(annotations);
            await m.createTable(settings);
          }
          if (from < 4) {
            await m.addColumn(books, books.contentHash);
          }
          if (from < 5) {
            await m.createTable(distillJobs);
            await m.createTable(distillUnits);
            await m.createTable(distillArtifacts);
          }
        },
      );
}
