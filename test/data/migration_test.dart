import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';

void main() {
  test('upgrades a v5 database through v8', () async {
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

    expect(db.schemaVersion, 9);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();
    expect(names, containsAll(['categories', 'book_categories']));

    final indexes = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
    expect(
      indexNames,
      containsAll(['categories_name', 'book_categories_category']),
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
    expect(version.read<int>('user_version'), 9);

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

    expect(db.schemaVersion, 9);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();
    expect(names, contains('translation_caches'));

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
      containsAll(['books', 'chapters', 'translation_caches']),
    );

    await db.close();
  });
}
