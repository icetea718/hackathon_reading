import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';

void main() {
  test('upgrades a v5 database by adding the category tables', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) => raw.execute('PRAGMA user_version = 5;'),
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

    await db.close();
  });

  test('upgrades a v6 database by adding the translation cache', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) => raw.execute('PRAGMA user_version = 6;'),
    ));

    expect(db.schemaVersion, 7);
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
