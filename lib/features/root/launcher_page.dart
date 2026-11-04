import 'package:flutter/material.dart';

import 'app_mode.dart';

/// Cold-start fork: pick 搜 (agent chat) or 阅 (the bookshelf).
///
/// Purely local: no database read, no network probe, so the launcher is up
/// immediately and the app never pays for a shell it was not asked to show.
class LauncherPage extends StatelessWidget {
  const LauncherPage({super.key, required this.onPick});

  final ValueChanged<AppMode> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('今天想做什么？', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = MediaQuery.sizeOf(context).width >= 720;
                  final cards = [
                    _ModeCard(
                      key: const Key('launcher-search'),
                      icon: Icons.travel_explore_outlined,
                      label: '搜',
                      hint: '问点什么，也可以让它上网找',
                      onTap: () => onPick(AppMode.search),
                    ),
                    _ModeCard(
                      key: const Key('launcher-read'),
                      icon: Icons.menu_book_outlined,
                      label: '阅',
                      hint: '继续读书架上的书',
                      onTap: () => onPick(AppMode.read),
                    ),
                  ];
                  if (wide) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: cards[0]),
                        const SizedBox(width: 16),
                        Flexible(child: cards[1]),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      cards[0],
                      const SizedBox(height: 16),
                      cards[1],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(label, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
