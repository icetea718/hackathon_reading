import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two top-level experiences: reading the shelf, and a general agent chat.
enum AppMode { read, search }

/// Which shell the app is showing. `null` means the launcher is up, which is
/// the state on every cold start: the choice is deliberately not remembered.
class AppModeNotifier extends Notifier<AppMode?> {
  @override
  AppMode? build() => null;

  void select(AppMode mode) => state = mode;

  void reset() => state = null;
}

final modeProvider =
    NotifierProvider<AppModeNotifier, AppMode?>(AppModeNotifier.new);
