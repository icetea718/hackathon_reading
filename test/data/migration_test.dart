import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';

void main() {
  test('upgrades a v5 database with categories and the comic flag', () async {
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
      },
    ));

    expect(db.schemaVersion, 7);
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

    await db.close();
  });
}
