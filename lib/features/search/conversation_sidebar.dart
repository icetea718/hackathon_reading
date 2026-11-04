import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Thread list shown beside the transcript, or inside a drawer on narrow windows.
class ConversationSidebar extends ConsumerWidget {
  const ConversationSidebar({
    super.key,
    required this.activeThreadId,
    required this.onPick,
    required this.onNew,
  });

  /// Null when the current conversation has not been persisted yet.
  final String? activeThreadId;
  final ValueChanged<String> onPick;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final threads = ref.watch(chatThreadsProvider);

    return Container(
      key: const Key('chat-sidebar'),
      width: 264,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: FilledButton.tonalIcon(
              key: const Key('sidebar-new'),
              onPressed: onNew,
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: const Text('新对话'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: threads.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      '还没有对话',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final selected = row.id == activeThreadId;
                    return ListTile(
                      key: Key('sidebar-thread-${row.id}'),
                      dense: true,
                      selected: selected,
                      title: Text(
                        row.title.isEmpty ? '新对话' : row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: '删除对话',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _delete(context, ref, row.id),
                      ),
                      onTap: () => onPick(row.id),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    await ref.read(chatThreadRepositoryProvider).delete(id);
  }
}
