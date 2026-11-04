import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';

void main() {
  late AppDatabase db;
  late ChapterRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ChapterRepository(db);
    await repo.replaceForBook('b1', [
      const Chapter(
        id: 'c0',
        bookId: 'b1',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: 10,
        contentText: '第一章的正文内容',
      ),
      const Chapter(
        id: 'c1',
        bookId: 'b1',
        index: 1,
        title: '第二章',
        startOffset: 10,
        endOffset: 20,
        contentText: '第二章的正文内容',
        level: 2,
      ),
    ]);
  });
  tearDown(() => db.close());

  test('summaries load titles and offsets without content', () async {
    final chapters = await repo.getSummariesForBook('b1');

    expect(chapters.map((c) => c.title), ['第一章', '第二章']);
    expect(chapters.map((c) => c.startOffset), [0, 10]);
    expect(chapters.map((c) => c.endOffset), [10, 20]);
    expect(chapters.every((c) => c.contentText.isEmpty), isTrue);
  });

  test('summaries keep the chapter level', () async {
    final chapters = await repo.getSummariesForBook('b1');

    expect(chapters.map((c) => c.level), [1, 2]);
  });

  test('full chapters keep the chapter level', () async {
    final chapters = await repo.getForBook('b1');

    expect(chapters.map((c) => c.level), [1, 2]);
  });

  test('content loads for a single chapter', () async {
    expect(await repo.getContent('b1', 1), '第二章的正文内容');
  });

  test('content is null for an unknown chapter', () async {
    expect(await repo.getContent('b1', 9), isNull);
    expect(await repo.getContent('other', 0), isNull);
  });
}
