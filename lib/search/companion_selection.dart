import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which companion threads of a book the 搜 answers should remember.
///
/// Null means automatic (the newest few); an empty set means the reader
/// unchecked everything, which is not the same as never having chosen.
class CompanionSelectionNotifier extends Notifier<Set<String>?> {
  CompanionSelectionNotifier(this.bookId);

  final String bookId;

  @override
  Set<String>? build() => null;

  void setSelection(Set<String> threadIds) => state = {...threadIds};

  void reset() => state = null;
}

final companionSelectionProvider =
    NotifierProvider.family<CompanionSelectionNotifier, Set<String>?, String>(
  CompanionSelectionNotifier.new,
);
