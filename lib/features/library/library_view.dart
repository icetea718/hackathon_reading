import '../../domain/models/book.dart';
import '../../domain/models/category.dart';

const String uncategorizedCategoryId = '__uncategorized__';

class CategorySummary {
  const CategorySummary({required this.category, required this.bookCount});

  final Category category;
  final int bookCount;
}

class LibraryView {
  const LibraryView({
    required this.allBooks,
    required this.visibleBooks,
    required this.categories,
    required this.categoryIdsByBook,
    required this.progressByBook,
    required this.uncategorizedCount,
    required this.effectiveCategoryId,
  });

  final List<Book> allBooks;
  final List<Book> visibleBooks;
  final List<CategorySummary> categories;
  final Map<String, Set<String>> categoryIdsByBook;
  final Map<String, double> progressByBook;
  final int uncategorizedCount;
  final String? effectiveCategoryId;
}

List<Book> filterBooks(
  List<Book> books,
  String query,
  String? categoryId,
  Map<String, Set<String>> categoryIdsByBook,
) {
  final normalized = query.trim().toLowerCase();
  return books.where((book) {
    if (normalized.isNotEmpty &&
        !book.title.toLowerCase().contains(normalized) &&
        !book.author.toLowerCase().contains(normalized)) {
      return false;
    }
    if (categoryId == null) return true;
    final memberships = categoryIdsByBook[book.id] ?? const <String>{};
    if (categoryId == uncategorizedCategoryId) return memberships.isEmpty;
    return memberships.contains(categoryId);
  }).toList();
}

List<Book> sortBooks(List<Book> books) {
  final sorted = [...books];
  sorted.sort((a, b) {
    final aTime = a.lastOpenedAt ?? a.addedAt;
    final bTime = b.lastOpenedAt ?? b.addedAt;
    final byTime = bTime.compareTo(aTime);
    if (byTime != 0) return byTime;
    final byTitle = a.title.compareTo(b.title);
    if (byTitle != 0) return byTitle;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

List<CategorySummary> buildCategorySummaries(
  List<Category> categories,
  Map<String, Set<String>> categoryIdsByBook,
) {
  final counts = <String, int>{};
  for (final ids in categoryIdsByBook.values) {
    for (final id in ids) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return [
    for (final category in categories)
      CategorySummary(
        category: category,
        bookCount: counts[category.id] ?? 0,
      ),
  ];
}

int countUncategorized(
  List<Book> books,
  Map<String, Set<String>> categoryIdsByBook,
) {
  return books
      .where(
        (book) =>
            (categoryIdsByBook[book.id] ?? const <String>{}).isEmpty,
      )
      .length;
}
