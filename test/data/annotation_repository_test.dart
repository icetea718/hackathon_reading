import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/annotation_repository.dart';
import 'package:coread/domain/models/annotation.dart';

void main() {
  late AppDatabase db;
  late AnnotationRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AnnotationRepository(db);
  });
  tearDown(() => db.close());

  Annotation sample(
    String id,
    int anchorStart, {
    String bookId = 'b1',
    AnnotationType type = AnnotationType.bookmark,
  }) {
    return Annotation(
      id: id,
      bookId: bookId,
      chapterId: 'b1-c0',
      type: type,
      anchorStart: anchorStart,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  test('saves and lists annotations ordered by anchor', () async {
    await repo.upsert(sample('a2', 20));
    await repo.upsert(sample('a1', 10));

    final stored = await repo.getForBook('b1');
    expect(stored.map((a) => a.id), ['a1', 'a2']);
    expect(stored.first.anchorStart, 10);
    expect(stored.first.type, AnnotationType.bookmark);
  });

  test('filters by type', () async {
    await repo.upsert(sample('bookmark', 10));
    await repo.upsert(sample(
      'highlight',
      20,
      type: AnnotationType.highlight,
    ));

    final bookmarks =
        await repo.getForBook('b1', type: AnnotationType.bookmark);
    expect(bookmarks.map((a) => a.id), ['bookmark']);
  });

  test('deletes one annotation', () async {
    await repo.upsert(sample('a1', 10));
    await repo.delete('a1');
    expect(await repo.getForBook('b1'), isEmpty);
  });

  test('deletes all annotations for a book', () async {
    await repo.upsert(sample('a1', 10));
    await repo.upsert(sample('other', 30, bookId: 'b2'));

    await repo.deleteForBook('b1');
    expect(await repo.getForBook('b1'), isEmpty);
    expect(await repo.getForBook('b2'), hasLength(1));
  });
}
