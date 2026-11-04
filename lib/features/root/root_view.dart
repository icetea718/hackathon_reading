import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/app_shell.dart';
import 'app_mode.dart';
import 'launcher_page.dart';
import 'mode_switch.dart';

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
      AppMode.search => const _SearchPlaceholder(),
    };
  }
}

class _SearchPlaceholder extends ConsumerWidget {
  const _SearchPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: const Key('search-shell'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                ModeSwitch(
                  mode: AppMode.search,
                  axis: Axis.horizontal,
                  keyPrefix: 'search',
                  onChanged: (mode) =>
                      ref.read(modeProvider.notifier).select(mode),
                ),
              ],
            ),
          ),
          const Expanded(child: Center(child: Text('搜'))),
        ],
      ),
    );
  }
}
