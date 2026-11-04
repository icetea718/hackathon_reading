import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/companion_chat.dart';
import '../../search/book_memory.dart';
import '../../search/companion_selection.dart';

/// Messages of one companion thread, loaded when its tile expands.
final bookCompanionMessagesProvider = FutureProvider.autoDispose
    .family<List<CompanionMessage>, String>((ref, threadId) {
  return ref.watch(companionChatRepositoryProvider).messagesForThread(threadId);
});

Future<void> showBookMemorySheet(BuildContext context, String bookId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BookMemorySheet(bookId: bookId),
  );
}

/// The 本书资料 panel: what the reader left in one book, and which companion
/// conversations the 搜 answers should carry.
class BookMemorySheet extends ConsumerWidget {
  const BookMemorySheet({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(bookMemoryProvider(bookId));
    final theme = Theme.of(context);

    return SizedBox(
      key: const Key('book-memory-sheet'),
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: memory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('资料加载失败：$error')),
        data: (memory) {
          if (memory == null) {
            return const Center(child: Text('书架里找不到这本书'));
          }
          return DefaultTabController(
            length: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '本书资料 · ${memory.bookTitle}',
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: '书签'),
                    Tab(text: '高亮'),
                    Tab(text: '笔记'),
                    Tab(text: '陪读对话'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _EntryList(
                        entries: memory.bookmarks,
                        emptyText: '还没有书签',
                        showQuotes: false,
                      ),
                      _EntryList(
                        entries: memory.highlights,
                        emptyText: '还没有高亮',
                        showQuotes: true,
                      ),
                      _EntryList(
                        entries: memory.notes,
                        emptyText: '还没有笔记',
                        showQuotes: false,
                      ),
                      _CompanionTab(bookId: bookId, memory: memory),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.entries,
    required this.emptyText,
    required this.showQuotes,
  });

  final List<BookAnnotationEntry> entries;
  final String emptyText;
  final bool showQuotes;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(child: Text(emptyText));
    }
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          dense: true,
          title: Text(entry.label, style: theme.textTheme.labelMedium),
          subtitle: entry.text.isEmpty
              ? null
              : Text(showQuotes ? '「${entry.text}」' : entry.text),
        );
      },
    );
  }
}

class _CompanionTab extends ConsumerWidget {
  const _CompanionTab({required this.bookId, required this.memory});

  final String bookId;
  final BookMemory memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(companionSelectionProvider(bookId));
    final checked = selection ?? memory.companionDigest.threadIds;
    final notifier = ref.read(companionSelectionProvider(bookId).notifier);

    if (memory.companionThreads.isEmpty) {
      return const Center(child: Text('还没有陪读对话'));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (selection != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: TextButton(
                key: const Key('companion-reset'),
                onPressed: notifier.reset,
                child: const Text('恢复默认'),
              ),
            ),
          ),
        for (final thread in memory.companionThreads)
          ExpansionTile(
            key: Key('companion-thread-${thread.id}'),
            leading: Checkbox(
              key: Key('companion-check-${thread.id}'),
              value: checked.contains(thread.id),
              onChanged: (value) {
                final next = {...checked};
                if (value ?? false) {
                  next.add(thread.id);
                } else {
                  next.remove(thread.id);
                }
                notifier.setSelection(next);
              },
            ),
            title: Text(thread.title.isEmpty ? '新对话' : thread.title),
            subtitle: Text(
              '第 ${thread.chapterIndex + 1} 章 ${thread.chapterTitle}'
              ' · ${thread.messageCount} 条',
            ),
            children: [_CompanionMessages(threadId: thread.id)],
          ),
      ],
    );
  }
}

class _CompanionMessages extends ConsumerWidget {
  const _CompanionMessages({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(bookCompanionMessagesProvider(threadId));
    final theme = Theme.of(context);
    return messages.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('消息加载失败：$error'),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('这段对话还没有消息'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final message in rows)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 6),
                child: Text(
                  message.role == CompanionRole.user
                      ? '读者：${message.content}'
                      : '助手：${message.content}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}
