import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late BookRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BookRepository(db);
  });
  tearDown(() => db.close());

  Book sample(String id) => Book(
        id: id,
        title: '测试书',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/$id.txt',
        addedAt: DateTime(2026, 1, 1),
      );

  test('inserts, lists, and deletes books', () async {
    await repo.upsert(sample('b1'));
    expect((await repo.getAll()).single.title, '测试书');
    await repo.delete('b1');
    expect(await repo.getAll(), isEmpty);
  });

  test('orders by addedAt descending', () async {
    await repo.upsert(sample('old'));
    await repo.upsert(Book(
      id: 'new',
      title: '新书',
      author: '',
      format: BookFormat.epub,
      sourcePath: 'C:/books/new.epub',
      addedAt: DateTime(2026, 2, 1),
    ));
    expect((await repo.getAll()).map((b) => b.id), ['new', 'old']);
  });

  test('round-trips the comic flag', () async {
    await repo.upsert(Book(
      id: 'comic',
      title: '漫画',
      author: '',
      format: BookFormat.epub,
      sourcePath: 'C:/books/comic.epub',
      comic: true,
      addedAt: DateTime(2026, 1, 1),
    ));

    expect((await repo.getById('comic'))!.comic, isTrue);
    expect((await repo.getById('b1')), isNull);
  });

  test('parses extensions case-insensitively', () {
    expect(BookFormat.fromExtension('A.TXT'), BookFormat.txt);
    expect(BookFormat.fromExtension('book.epub'), BookFormat.epub);
    expect(BookFormat.fromExtension('x.doc'), isNull);
  });
}
