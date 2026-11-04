import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../memory_book/memory_book_models.dart';
import '../illustration/illustration_composer_page.dart';
import '../memory_book/memory_book_dialogs.dart';
import '../memory_book/memory_book_page.dart';
import '../memory_book/memory_book_providers.dart';

/// Shown from the companion panel while reading: turn the current page into
/// an illustration, or open / create a memory book right away.
class CompanionMemorySheet extends ConsumerWidget {
  const CompanionMemorySheet({
    super.key,
    required this.initialText,
    required this.contextLabel,
  });

  final String initialText;
  final String contextLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(memoryBookListProvider);
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        key: const Key('companion-memory-sheet'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('回忆录', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '读到哪里，就把哪一页收进来；也可以先新建一本。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              key: const Key('companion-memory-generate'),
              leading: const Icon(Icons.auto_awesome),
              title: const Text('把这一页画成插画'),
              subtitle: const Text('用这一页的文字生成，保存时可选或新建回忆录'),
              onTap: () => _generate(context),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                '我的回忆录',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: books.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('回忆录加载失败：$error'),
                ),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Text('还没有回忆录，先新建一本。'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final book in list)
                            ListTile(
                              key: Key('companion-memory-book-${book.id}'),
                              leading:
                                  const Icon(Icons.photo_album_outlined),
                              title: Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('${book.pageCount} 张照片'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openBook(context, book),
                            ),
                        ],
                      ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('companion-memory-create'),
              leading: const Icon(Icons.add),
              title: const Text('新建回忆录…'),
              subtitle: const Text('建好后直接打开，边读边收'),
              onTap: () => _create(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _generate(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => IllustrationComposerPage(
          initialText: initialText,
          contextLabel: contextLabel,
        ),
      ),
    );
  }

  void _openBook(BuildContext context, MemoryBook book) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryBookPage(bookId: book.id),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await promptMemoryBookName(context);
    if (name == null || !context.mounted) return;
    final navigator = Navigator.of(context);
    try {
      final store = await ref.read(memoryBookStoreProvider.future);
      final book = await store.createBook(name);
      if (!context.mounted) return;
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => MemoryBookPage(bookId: book.id),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('新建失败：$error')));
    }
  }
}
