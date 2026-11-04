import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The book the reader attached to the 搜 conversation, if any.
///
/// Shell-wide rather than per thread: switching conversations keeps the book,
/// because the reader is usually still asking about the same one.
class SearchBookNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String bookId) => state = bookId;

  void clear() => state = null;
}

final searchBookProvider =
    NotifierProvider<SearchBookNotifier, String?>(SearchBookNotifier.new);
