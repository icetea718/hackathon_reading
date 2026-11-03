import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';

void main() {
  test('upgrades a v5 database by adding the category tables', () async {
    final db = AppDatabase(NativeDatabase.memory(
      setup: (raw) => raw.execute('PRAGMA user_version = 5;'),
    ));

    expect(db.schemaVersion, 6);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();
    expect(names, containsAll(['categories', 'book_categories']));

    await db.close();
  });
}
