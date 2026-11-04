import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';

void main() {
  test('upgrades a v5 database through v11', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 5;');
        raw.execute(
          'CREATE TABLE books ('
          'id TEXT NOT NULL PRIMARY KEY, '
          "title TEXT NOT NULL, "
          "author TEXT NOT NULL DEFAULT '', "
          'format TEXT NOT NULL, '
          'source_path TEXT NOT NULL, '
          'cover_path TEXT, '
          'content_hash TEXT, '
          'added_at INTEGER NOT NULL, '
          'last_opened_at INTEGER)',
        );
        raw.execute(
          'CREATE TABLE chapters ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'book_id TEXT NOT NULL, '
          'chapter_index INTEGER NOT NULL, '
          'title TEXT NOT NULL, '
          'start_offset INTEGER NOT NULL, '
          'end_offset INTEGER NOT NULL, '
          'content_text TEXT NOT NULL)',
        );
        raw.execute(
          "INSERT INTO chapters "
          '(id, book_id, chapter_index, title, start_offset, end_offset, '
          "content_text) VALUES ('c1', 'b1', 0, '旧章', 0, 10, '正文')",
        );
      },
    ));

    expect(db.schemaVersion, 12);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'categories',
        'book_categories',
        'chat_threads',
        'chat_messages',
        'translation_caches',
      ]),
    );

    final indexes = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
    expect(
      indexNames,
      containsAll([
        'categories_name',
        'book_categories_category',
        'chat_threads_updated',
        'chat_messages_thread',
      ]),
    );

    await db.customStatement(
      'INSERT INTO books (id, title, format, source_path, added_at) '
      "VALUES ('b1', '旧书', 'txt', 'old.txt', 0)",
    );
    final comic = await db
        .customSelect('SELECT comic FROM books WHERE id = ?',
            variables: [Variable.withString('b1')])
        .getSingle();
    expect(comic.read<bool>('comic'), isFalse);

    final chapter = await db
        .customSelect('SELECT level FROM chapters WHERE id = ?',
            variables: [Variable.withString('c1')])
        .getSingle();
    expect(chapter.read<int>('level'), 1);

    await db.close();
  });

  test('upgrades a v7 database whose chapters table already has level', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 7;');
        raw.execute(
          'CREATE TABLE chapters ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'book_id TEXT NOT NULL, '
          'chapter_index INTEGER NOT NULL, '
          'title TEXT NOT NULL, '
          'start_offset INTEGER NOT NULL, '
          'end_offset INTEGER NOT NULL, '
          'content_text TEXT NOT NULL, '
          'level INTEGER NOT NULL DEFAULT 1)',
        );
        raw.execute(
          "INSERT INTO chapters "
          '(id, book_id, chapter_index, title, start_offset, end_offset, '
          "content_text, level) VALUES ('c1', 'b1', 0, '旧章', 0, 10, '正文', 2)",
        );
      },
    ));

    final chapter = await db
        .customSelect(
          'SELECT level FROM chapters WHERE id = ?',
          variables: [Variable.withString('c1')],
        )
        .getSingle();
    expect(chapter.read<int>('level'), 2);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 12);

    await db.close();
  });

  test('creates the translation cache when upgrading from v5', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 5;');
        raw.execute(
          'CREATE TABLE books ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'title TEXT NOT NULL, '
          "author TEXT NOT NULL DEFAULT '', "
          'format TEXT NOT NULL, '
          'source_path TEXT NOT NULL, '
          'cover_path TEXT, '
          'content_hash TEXT, '
          'added_at INTEGER NOT NULL, '
          'last_opened_at INTEGER)',
        );
        raw.execute(
          'CREATE TABLE chapters ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'book_id TEXT NOT NULL, '
          'chapter_index INTEGER NOT NULL, '
          'title TEXT NOT NULL, '
          'start_offset INTEGER NOT NULL, '
          'end_offset INTEGER NOT NULL, '
          'content_text TEXT NOT NULL)',
        );
      },
    ));

    expect(db.schemaVersion, 12);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();
    expect(names, contains('translation_caches'));

    await db.close();
  });

  test('upgrades a v9 database that lacks the newly merged tables', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 9;');
      },
    ));

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll(['chat_threads', 'chat_messages', 'translation_caches']),
    );

    await db.close();
  });

  test('creates every table on a fresh database', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'books',
        'chapters',
        'translation_caches',
        'chat_threads',
        'chat_messages',
      ]),
    );

    await db.close();
  });

  test('upgrades a v9 database to the companion chat tables', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 9;');
      },
    ));

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(names, containsAll(['companion_threads', 'companion_messages']));

    final indexes = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
    expect(
      indexNames,
      containsAll([
        'companion_threads_book_chapter',
        'companion_messages_thread_seq',
      ]),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 12);
    await db.close();
  });

  test('re-running the v11 migration tolerates an existing table', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 9;');
        raw.execute(
          'CREATE TABLE companion_threads ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'book_id TEXT NOT NULL, '
          'chapter_index INTEGER NOT NULL, '
          'chapter_title TEXT NOT NULL, '
          'title TEXT NOT NULL, '
          'created_at INTEGER NOT NULL, '
          'updated_at INTEGER NOT NULL)',
        );
        raw.execute(
          'CREATE INDEX companion_threads_book_chapter '
          'ON companion_threads (book_id, chapter_index)',
        );
      },
    ));

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(names, contains('companion_messages'));
    await db.close();
  });

  test('upgrades a v10 companion-only database to the search chat tables',
      () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 10;');
        raw.execute(
          'CREATE TABLE companion_threads ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'book_id TEXT NOT NULL, '
          'chapter_index INTEGER NOT NULL, '
          'chapter_title TEXT NOT NULL, '
          'title TEXT NOT NULL, '
          'created_at INTEGER NOT NULL, '
          'updated_at INTEGER NOT NULL)',
        );
        raw.execute(
          'CREATE INDEX companion_threads_book_chapter '
          'ON companion_threads (book_id, chapter_index)',
        );
        raw.execute(
          'CREATE TABLE companion_messages ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'thread_id TEXT NOT NULL, '
          'role TEXT NOT NULL, '
          'content TEXT NOT NULL, '
          'seq INTEGER NOT NULL, '
          'created_at INTEGER NOT NULL)',
        );
        raw.execute(
          'CREATE UNIQUE INDEX companion_messages_thread_seq '
          'ON companion_messages (thread_id, seq)',
        );
      },
    ));

    final names = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get())
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(names, containsAll(['chat_threads', 'chat_messages']));

    final indexNames = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
            .get())
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(
      indexNames,
      containsAll(['chat_threads_updated', 'chat_messages_thread']),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 12);
    await db.close();
  });

  test('upgrades a v10 search-only database to the companion tables',
      () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 10;');
        raw.execute(
          'CREATE TABLE chat_threads ('
          'id TEXT NOT NULL PRIMARY KEY, '
          "title TEXT NOT NULL DEFAULT '', "
          'created_at TEXT NOT NULL, '
          'updated_at TEXT NOT NULL)',
        );
        raw.execute(
          'CREATE INDEX chat_threads_updated ON chat_threads (updated_at)',
        );
        raw.execute(
          'CREATE TABLE chat_messages ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'thread_id TEXT NOT NULL, '
          'role TEXT NOT NULL, '
          'content TEXT NOT NULL, '
          'sources_json TEXT, '
          "status TEXT NOT NULL DEFAULT 'complete', "
          'created_at TEXT NOT NULL)',
        );
        raw.execute(
          'CREATE INDEX chat_messages_thread '
          'ON chat_messages (thread_id, created_at)',
        );
      },
    ));

    final names = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get())
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(
      names,
      containsAll(['companion_threads', 'companion_messages']),
    );

    final indexNames = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
            .get())
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(
      indexNames,
      containsAll([
        'companion_threads_book_chapter',
        'companion_messages_thread_seq',
      ]),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 12);
    await db.close();
  });

  test('upgrades a v11 search database with a book column', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 11;');
        raw.execute(
          'CREATE TABLE chat_threads ('
          'id TEXT NOT NULL PRIMARY KEY, '
          "title TEXT NOT NULL DEFAULT '', "
          'created_at TEXT NOT NULL, '
          'updated_at TEXT NOT NULL)',
        );
        raw.execute(
          'CREATE INDEX chat_threads_updated ON chat_threads (updated_at)',
        );
        raw.execute(
          "INSERT INTO chat_threads (id, title, created_at, updated_at) "
          "VALUES ('t1', '旧对话', '2026-11-04T00:00:00.000', "
          "'2026-11-04T00:00:00.000')",
        );
      },
    ));

    final columns = await db
        .customSelect('PRAGMA table_info(chat_threads)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('book_id'),
    );

    final row = await db
        .customSelect("SELECT book_id FROM chat_threads WHERE id = 't1'")
        .getSingle();
    expect(row.read<String?>('book_id'), null);

    final indexNames = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
            .get())
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(indexNames, contains('chat_threads_book'));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 12);
    await db.close();
  });

  test('re-running the v12 migration tolerates an existing column', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 11;');
        raw.execute(
          'CREATE TABLE chat_threads ('
          'id TEXT NOT NULL PRIMARY KEY, '
          "title TEXT NOT NULL DEFAULT '', "
          'created_at TEXT NOT NULL, '
          'updated_at TEXT NOT NULL, '
          'book_id TEXT)',
        );
        raw.execute(
          'CREATE INDEX chat_threads_updated ON chat_threads (updated_at)',
        );
        raw.execute(
          'CREATE INDEX chat_threads_book ON chat_threads (book_id, updated_at)',
        );
      },
    ));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 12);
    await db.close();
  });
}
