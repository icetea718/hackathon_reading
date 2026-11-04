import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/category_pane.dart';
import '../library/library_page.dart';
import '../memory_book/memory_books_page.dart';
import '../root/app_mode.dart';
import '../root/mode_switch.dart';
import '../settings/settings_page.dart';
import 'home_providers.dart';
import 'section_rail.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(selectedSectionProvider);
    return Scaffold(
      body: Row(
        children: [
          SectionRail(
            activeSection: section,
            leading: ModeSwitch(
              mode: AppMode.read,
              keyPrefix: 'rail',
              onChanged: (mode) =>
                  ref.read(modeProvider.notifier).select(mode),
            ),
            onSelectSection: (value) =>
                ref.read(selectedSectionProvider.notifier).select(value),
            onSettings: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
            },
            onMemory: () =>
                ref.read(selectedSectionProvider.notifier).select(
                      AppSection.memory,
                    ),
          ),
          Expanded(
            child: switch (section) {
              AppSection.bookshelf => const Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CategoryPane(),
                  Expanded(child: BookshelfView()),
                ],
              ),
              AppSection.memory => const MemoryBooksPage(),
              AppSection.companion => const _CompanionPlaceholder(),
            },
          ),
        ],
      ),
    );
  }
}

class _CompanionPlaceholder extends StatelessWidget {
  const _CompanionPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('陪读对话工作区即将上线', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '可以从阅读页的陪读按钮打开对话面板',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
