import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'converters.dart';
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
    ChatThreads,
    ChatMessages,
    TranslationCaches,
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
          Future<bool> hasTable(String name) async {
            final rows = await m.database.customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
              variables: [Variable.withString(name)],
            ).get();
            return rows.isNotEmpty;
          }

          if (from < 9) {
            await m.createTable(translationCaches);
          }
          if (from < 10) {
            // Both branches used schema version 9, so a v9 database may have
            // only one of these table groups. Create whichever is missing.
            if (!await hasTable('chat_threads')) {
              await m.createTable(chatThreads);
              await m.create(chatThreadsUpdated);
            }
            if (!await hasTable('chat_messages')) {
              await m.createTable(chatMessages);
              await m.create(chatMessagesThread);
            }
            if (!await hasTable('translation_caches')) {
              await m.createTable(translationCaches);
            }
          }
        },
      );
}
