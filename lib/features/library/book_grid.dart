import 'package:flutter/material.dart';

import '../../domain/models/book.dart';
import 'book_card.dart';

class BookGrid extends StatelessWidget {
  const BookGrid({
    super.key,
    required this.books,
    required this.progressByBook,
    required this.manageMode,
    required this.selectedBookIds,
    required this.onOpen,
    required this.onToggleSelected,
    required this.onAddToCategory,
    required this.onDelete,
    required this.onDistill,
  });

  final List<Book> books;
  final Map<String, double> progressByBook;
  final bool manageMode;
  final Set<String> selectedBookIds;
  final ValueChanged<Book> onOpen;
  final ValueChanged<Book> onToggleSelected;
  final ValueChanged<Book> onAddToCategory;
  final ValueChanged<Book> onDelete;
  final ValueChanged<Book> onDistill;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 320,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return BookCard(
          key: Key('book-card-${book.id}'),
          book: book,
          percent: progressByBook[book.id],
          manageMode: manageMode,
          selected: selectedBookIds.contains(book.id),
          onOpen: () => onOpen(book),
          onToggleSelected: () => onToggleSelected(book),
          onAddToCategory: () => onAddToCategory(book),
          onDelete: () => onDelete(book),
          onDistill: () => onDistill(book),
        );
      },
    );
  }
}
