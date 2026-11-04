import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sticky for the app session so reopening the panel does not bring back a
/// hint the reader already dismissed.
final companionMemoryHintHiddenProvider =
    NotifierProvider<CompanionMemoryHintHidden, bool>(
  CompanionMemoryHintHidden.new,
);

class CompanionMemoryHintHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void hide() => state = true;
}
