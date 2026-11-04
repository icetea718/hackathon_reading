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
    CompanionThreads,
    CompanionMessages,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.defaults() : super(driftDatabase(name: 'reader'));

  @override
  int get schemaVersion => 10;

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
          if (from < 10) {
            final tables = await m.database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table'",
                )
                .get();
            final names =
                tables.map((row) => row.read<String>('name')).toSet();
            if (!names.contains('companion_threads')) {
              await m.createTable(companionThreads);
            }
            if (!names.contains('companion_messages')) {
              await m.createTable(companionMessages);
            }
            final indexes = await m.database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index'",
                )
                .get();
            final indexNames =
                indexes.map((row) => row.read<String>('name')).toSet();
            if (!indexNames.contains('companion_threads_book_chapter')) {
              await m.create(companionThreadsBookChapter);
            }
            if (!indexNames.contains('companion_messages_thread_seq')) {
              await m.create(companionMessagesThreadSeq);
            }
          }
        },
      );
}
