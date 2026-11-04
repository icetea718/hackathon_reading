import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/category.dart';
import 'library_view.dart';

class SelectedCategory extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

class ManageMode extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) => state = value;
}

class SelectedBooks extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) {
    final next = {...state};
    if (!next.add(id)) next.remove(id);
    state = next;
  }

  void clear() => state = const {};
}

final selectedCategoryProvider =
    NotifierProvider<SelectedCategory, String?>(SelectedCategory.new);
final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);
final manageModeProvider =
    NotifierProvider<ManageMode, bool>(ManageMode.new);
final selectedBookIdsProvider =
    NotifierProvider<SelectedBooks, Set<String>>(SelectedBooks.new);

final libraryViewProvider = Provider<AsyncValue<LibraryView>>((ref) {
  final booksAsync = ref.watch(bookListProvider);
  final categories =
      ref.watch(categoriesProvider).value ?? const <Category>[];
  final memberships = ref.watch(bookCategoryMembershipsProvider).value ??
      const <BookCategoryRecord>[];
  final percents =
      ref.watch(progressPercentsProvider).value ?? const <String, double>{};
  final selected = ref.watch(selectedCategoryProvider);
  final query = ref.watch(searchQueryProvider);

  final categoryIdsByBook = <String, Set<String>>{};
  for (final row in memberships) {
    (categoryIdsByBook[row.bookId] ??= <String>{}).add(row.categoryId);
  }

  return booksAsync.whenData((books) {
    final String? effective;
    if (selected == null || selected == uncategorizedCategoryId) {
      effective = selected;
    } else {
      effective = categories.any((category) => category.id == selected)
          ? selected
          : null;
    }

    final sorted = sortBooks(books);
    return LibraryView(
      allBooks: books,
      visibleBooks: filterBooks(sorted, query, effective, categoryIdsByBook),
      categories: buildCategorySummaries(
        categories,
        categoryIdsByBook,
        existingBookIds: books.map((book) => book.id).toSet(),
      ),
      categoryIdsByBook: categoryIdsByBook,
      progressByBook: percents,
      uncategorizedCount: countUncategorized(books, categoryIdsByBook),
      effectiveCategoryId: effective,
    );
  });
});
