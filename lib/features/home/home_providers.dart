import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppSection { bookshelf, companion }

class SelectedSection extends Notifier<AppSection> {
  @override
  AppSection build() => AppSection.bookshelf;

  void select(AppSection section) => state = section;
}

final selectedSectionProvider =
    NotifierProvider<SelectedSection, AppSection>(SelectedSection.new);
