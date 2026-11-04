import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/progress_repository.dart';
import 'package:coread/domain/models/reading_progress.dart';

void main() {
  late AppDatabase db;
  late ProgressRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ProgressRepository(db);
  });

  tearDown(() => db.close());

  test('watchPercents emits a map of saved percentages', () async {
    await repo.save(ReadingProgress(
      bookId: 'b1',
      anchor: const ReadingAnchor(charOffset: 0),
      percent: 0.25,
      updatedAt: DateTime(2026, 1, 1),
    ));

    expect(await repo.watchPercents().first, {'b1': 0.25});
  });

  test('deleting progress removes the key from the map', () async {
    await repo.save(ReadingProgress(
      bookId: 'b1',
      anchor: const ReadingAnchor(charOffset: 0),
      percent: 0.25,
      updatedAt: DateTime(2026, 1, 1),
    ));
    await repo.save(ReadingProgress(
      bookId: 'b2',
      anchor: const ReadingAnchor(charOffset: 0),
      percent: 0.5,
      updatedAt: DateTime(2026, 1, 2),
    ));

    expect(await repo.watchPercents().first, {'b1': 0.25, 'b2': 0.5});

    await repo.delete('b1');

    expect(await repo.watchPercents().first, {'b2': 0.5});
  });
}
