import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/category.dart';
import 'package:hackathon_reading/features/library/library_view.dart';

Book book(
  String id, {
  String title = '书',
  String author = '',
  DateTime? added,
  DateTime? opened,
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      format: BookFormat.txt,
      sourcePath: 'C:/$id.txt',
      addedAt: added ?? DateTime(2026, 1, 1),
      lastOpenedAt: opened,
    );

void main() {
  test('filterBooks matches titles and authors case-insensitively', () {
    final books = [
      book('1', title: '三体'),
      book('2', title: 'Other', author: 'Liu Cixin'),
      book('3', title: '活着', author: '余华'),
    ];

    expect(filterBooks(books, '三', null, const {}).map((b) => b.id), ['1']);
    expect(filterBooks(books, 'liu', null, const {}).map((b) => b.id), ['2']);
    expect(filterBooks(books, '  ', null, const {}), books);
  });

  test('filterBooks filters by category and uncategorized', () {
    final books = [book('1'), book('2'), book('3')];
    final memberships = <String, Set<String>>{
      '1': {'c1'},
      '3': {},
    };

    expect(filterBooks(books, '', 'c1', memberships).map((b) => b.id), ['1']);
    expect(
      filterBooks(books, '', uncategorizedCategoryId, memberships)
          .map((b) => b.id),
      ['2', '3'],
    );
    expect(filterBooks(books, '', null, memberships), books);
  });

  test('sortBooks orders by recency then title', () {
    final books = [
      book('1', title: 'B', opened: DateTime(2026, 1, 3)),
      book('2', title: 'A', added: DateTime(2026, 1, 4)),
      book('3', title: 'A', added: DateTime(2026, 1, 2)),
      book('4', title: 'A', added: DateTime(2026, 1, 4)),
    ];

    expect(sortBooks(books).map((b) => b.id), ['2', '4', '1', '3']);
  });

  test('buildCategorySummaries counts members per category', () {
    final categories = [
      Category(
        id: 'c1',
        name: '科幻',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      Category(
        id: 'c2',
        name: '历史',
        sortOrder: 1,
        createdAt: DateTime(2026, 1, 2),
      ),
    ];
    final memberships = <String, Set<String>>{
      'b1': {'c1'},
      'b2': {'c1', 'c2'},
    };

    final summaries = buildCategorySummaries(categories, memberships);

    expect(summaries.map((s) => s.category.id), ['c1', 'c2']);
    expect(summaries.map((s) => s.bookCount), [2, 1]);
  });

  test('countUncategorized only counts books with no memberships', () {
    final books = [book('b1'), book('b2'), book('b3')];
    final memberships = <String, Set<String>>{
      'b1': {'c1'},
      'b2': {},
    };

    expect(countUncategorized(books, memberships), 2);
  });
}
