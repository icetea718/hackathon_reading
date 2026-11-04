import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/category_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CategoryRepository(db);
  });

  tearDown(() => db.close());

  test('creates categories in increasing sort order', () async {
    final first = await repo.create('  科幻  ');
    final second = await repo.create('历史');

    expect(first.name, '科幻');
    expect(first.sortOrder, 0);
    expect(second.sortOrder, 1);
  });

  test('trims names and rejects empty, overlong, and duplicate names', () async {
    await expectLater(
      repo.create('   '),
      throwsA(isA<InvalidCategoryNameException>()),
    );
    await expectLater(
      repo.create('x' * 21),
      throwsA(isA<InvalidCategoryNameException>()),
    );

    await repo.create('科幻');
    await expectLater(
      repo.create(' 科幻 '),
      throwsA(isA<DuplicateCategoryException>()),
    );
  });

  test('rename keeps the id and existing memberships', () async {
    final category = await repo.create('科幻');
    await repo.addBook('b1', category.id);

    await repo.rename(category.id, ' 历史 ');

    final all = await repo.getAll();
    expect(all.single.id, category.id);
    expect(all.single.name, '历史');
    final memberships = await repo.watchMemberships().first;
    expect(memberships.single.bookId, 'b1');
    expect(memberships.single.categoryId, category.id);
  });

  test('a book can belong to multiple categories', () async {
    final first = await repo.create('科幻');
    final second = await repo.create('历史');

    await repo.setBookCategories('b1', {first.id, second.id});

    final rows = await repo.watchMemberships().first;
    expect(rows.where((row) => row.bookId == 'b1'), hasLength(2));
  });

  test('add and remove are idempotent', () async {
    final category = await repo.create('科幻');

    await repo.addBook('b1', category.id);
    await repo.addBook('b1', category.id);
    expect(await repo.watchMemberships().first, hasLength(1));

    await repo.removeBook('b1', category.id);
    await repo.removeBook('b1', category.id);
    expect(await repo.watchMemberships().first, isEmpty);
  });

  test('setBookCategories replaces the whole set', () async {
    final first = await repo.create('科幻');
    final second = await repo.create('历史');

    await repo.setBookCategories('b1', {first.id});
    await repo.setBookCategories('b1', {second.id});

    final rows = await repo.watchMemberships().first;
    expect(rows.single.categoryId, second.id);
  });

  test('removeCategoryFromBooks only touches the selected books', () async {
    final category = await repo.create('科幻');
    await repo.addBook('b1', category.id);
    await repo.addBook('b2', category.id);

    await repo.removeCategoryFromBooks(category.id, {'b1'});

    final rows = await repo.watchMemberships().first;
    expect(rows.single.bookId, 'b2');
  });

  test('deleting a category removes memberships but keeps books', () async {
    final books = BookRepository(db);
    await books.upsert(Book(
      id: 'b1',
      title: '书',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/b1.txt',
      addedAt: DateTime(2026, 1, 1),
    ));
    final category = await repo.create('科幻');
    await repo.addBook('b1', category.id);

    await repo.delete(category.id);

    expect(await repo.getAll(), isEmpty);
    expect(await repo.watchMemberships().first, isEmpty);
    expect((await books.getAll()).single.id, 'b1');
  });

  test('deleteForBook removes that book from every category', () async {
    final first = await repo.create('科幻');
    final second = await repo.create('历史');
    await repo.addBook('b1', first.id);
    await repo.addBook('b1', second.id);
    await repo.addBook('b2', first.id);

    await repo.deleteForBook('b1');

    final rows = await repo.watchMemberships().first;
    expect(rows.single.bookId, 'b2');
  });
}
