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
    Categories,
    BookCategories,
    TranslationCaches,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.defaults() : super(driftDatabase(name: 'reader'));

  @override
  int get schemaVersion => 9;

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
          if (from < 6) {
            await m.createTable(categories);
            await m.createTable(bookCategories);
            await m.create(categoriesName);
            await m.create(bookCategoriesCategory);
          }
          if (from < 7) {
            await m.addColumn(books, books.comic);
          }
          if (from < 8) {
            final columns = await m.database
                .customSelect('PRAGMA table_info(chapters)')
                .get();
            final hasLevel =
                columns.any((row) => row.read<String>('name') == 'level');
            if (!hasLevel) {
              await m.addColumn(chapters, chapters.level);
            }
          }
          if (from < 9) {
            await m.createTable(translationCaches);
          }
        },
      );
}
