import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/app_shell.dart';
import '../search/search_shell.dart';
import 'app_mode.dart';
import 'launcher_page.dart';

/// Hosts the launcher until a mode is picked, then keeps both shells alive so
/// switching modes never cancels a running reply or loses scroll position.
///
/// A shell is only built once it has been visited: picking 搜 must not spin up
/// the bookshelf's database watchers behind the scenes.
class RootView extends ConsumerStatefulWidget {
  const RootView({super.key});

  @override
  ConsumerState<RootView> createState() => _RootViewState();
}

class _RootViewState extends ConsumerState<RootView> {
  final Set<AppMode> _built = <AppMode>{};

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(modeProvider);
    if (mode == null) {
      return LauncherPage(
        onPick: (picked) => ref.read(modeProvider.notifier).select(picked),
      );
    }

    _built.add(mode);
    return IndexedStack(
      index: AppMode.values.indexOf(mode),
      children: [
        for (final candidate in AppMode.values)
          if (_built.contains(candidate))
            _shellFor(candidate)
          else
            const SizedBox.shrink(),
      ],
    );
  }

  Widget _shellFor(AppMode mode) {
    return switch (mode) {
      AppMode.read => const AppShell(),
      AppMode.search => const SearchShell(),
    };
  }
}
