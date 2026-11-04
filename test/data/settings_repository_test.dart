import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('returns null for a missing key', () async {
    expect(await repo.get('missing'), isNull);
  });

  test('round-trips and overwrites values', () async {
    await repo.set('fontSize', '20');
    expect(await repo.get('fontSize'), '20');

    await repo.set('fontSize', '22');
    expect(await repo.get('fontSize'), '22');
  });
}
