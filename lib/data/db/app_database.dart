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
    CompanionThreads,
    CompanionMessages,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.defaults() : super(driftDatabase(name: 'reader'));

  @override
  int get schemaVersion => 13;

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

          Future<bool> hasIndex(String name) async {
            final rows = await m.database.customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
              variables: [Variable.withString(name)],
            ).get();
            return rows.isNotEmpty;
          }

          if (from < 9) {
            await m.createTable(translationCaches);
          }
          if (from < 11) {
            // Two branches both shipped as schema v10: one added the companion
            // tables, the other the search chat tables. A database upgraded
            // from either one lacks the other group, so create whichever is
            // missing. Existence checks keep this migration re-runnable.
            if (!await hasTable('companion_threads')) {
              await m.createTable(companionThreads);
            }
            if (!await hasIndex('companion_threads_book_chapter')) {
              await m.create(companionThreadsBookChapter);
            }
            if (!await hasTable('companion_messages')) {
              await m.createTable(companionMessages);
            }
            if (!await hasIndex('companion_messages_thread_seq')) {
              await m.create(companionMessagesThreadSeq);
            }
            if (!await hasTable('chat_threads')) {
              await m.createTable(chatThreads);
            }
            if (!await hasIndex('chat_threads_updated')) {
              await m.create(chatThreadsUpdated);
            }
            if (!await hasTable('chat_messages')) {
              await m.createTable(chatMessages);
            }
            if (!await hasIndex('chat_messages_thread')) {
              await m.create(chatMessagesThread);
            }
            if (!await hasTable('translation_caches')) {
              await m.createTable(translationCaches);
            }
          }
          if (from < 12) {
            // Older databases have chat_threads without book_id. Databases
            // created by the v11 block above already use the new definition,
            // so guard the column before adding it.
            final columns = await m.database
                .customSelect('PRAGMA table_info(chat_threads)')
                .get();
            final hasBookId =
                columns.any((row) => row.read<String>('name') == 'book_id');
            if (!hasBookId) {
              await m.addColumn(chatThreads, chatThreads.bookId);
            }
            if (!await hasIndex('chat_threads_book')) {
              await m.create(chatThreadsBook);
            }
          }
          if (from < 13) {
            // The v11 block creates chat_messages from the current definition,
            // so a table upgraded through it already has the column. A database
            // that never had the table (some fixtures) gets an empty PRAGMA
            // result, and the table definition covers it on creation.
            final columns = await m.database
                .customSelect('PRAGMA table_info(chat_messages)')
                .get();
            if (columns.isNotEmpty) {
              final hasSteps = columns
                  .any((row) => row.read<String>('name') == 'steps_json');
              if (!hasSteps) {
                await m.addColumn(chatMessages, chatMessages.stepsJson);
              }
            }
          }
        },
      );
}
