import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_providers.dart';
import 'library_view.dart';

class ManageBar extends ConsumerWidget {
  const ManageBar({
    super.key,
    required this.onAddToCategory,
    required this.onRemoveFromCategory,
    required this.onDelete,
  });

  final VoidCallback onAddToCategory;
  final VoidCallback onRemoveFromCategory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(manageModeProvider)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final selected = ref.watch(selectedBookIdsProvider);
    final categoryId = ref.watch(selectedCategoryProvider);
    final hasSelection = selected.isNotEmpty;
    final inRealCategory =
        categoryId != null && categoryId != uncategorizedCategoryId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        elevation: 3,
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text('已选 ${selected.length} 本'),
              const Spacer(),
              TextButton(
                onPressed: hasSelection ? onAddToCategory : null,
                child: const Text('添加到分类…'),
              ),
              TextButton(
                onPressed: hasSelection && inRealCategory
                    ? onRemoveFromCategory
                    : null,
                child: const Text('移出当前分类'),
              ),
              TextButton(
                onPressed: hasSelection ? onDelete : null,
                child: const Text('删除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
