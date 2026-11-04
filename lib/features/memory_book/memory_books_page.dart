import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../illustration/illustration_models.dart';
import '../../memory_book/memory_book_models.dart';
import '../illustration/illustration_composer_page.dart';
import '../illustration/illustration_jobs.dart';
import 'memory_book_dialogs.dart';
import 'memory_book_page.dart';
import 'memory_book_providers.dart';

class MemoryBooksPage extends ConsumerWidget {
  const MemoryBooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(memoryBookListProvider);
    final job = ref.watch(illustrationJobProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Row(
            children: [
              Text('回忆录', style: theme.textTheme.titleLarge),
              const SizedBox(width: 10),
              Text(
                '把生成的插画装订成册',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                key: const Key('memory-generate-button'),
                onPressed: () => _openComposer(context),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('生成插画'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('memory-new-button'),
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建回忆录'),
              ),
            ],
          ),
        ),
        if (job != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _CurrentGenerationCard(
              job: job,
              onOpen: () => _openJob(context, job),
              onStop: () => ref.read(illustrationJobProvider.notifier).cancel(),
              onDismiss: () =>
                  ref.read(illustrationJobProvider.notifier).dismiss(),
            ),
          ),
        Expanded(
          child: booksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('加载失败：$error')),
            data: (books) {
              if (books.isEmpty) {
                return _EmptyMemoryShelf(
                  onCreate: () => _create(context, ref),
                  onGenerate: () => _openComposer(context),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 300,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  return _MemoryBookCard(
                    key: Key('memory-book-card-${book.id}'),
                    book: book,
                    onOpen: () => _openBook(context, book),
                    onRename: () => _rename(context, ref, book),
                    onDelete: () => _delete(context, ref, book),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await promptMemoryBookName(context);
    if (name == null || !context.mounted) return;
    try {
      final store = await ref.read(memoryBookStoreProvider.future);
      await store.createBook(name);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('新建失败：$error')));
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    MemoryBook book,
  ) async {
    final name = await promptMemoryBookName(
      context,
      title: '重命名回忆录',
      initial: book.title,
    );
    if (name == null || !context.mounted) return;
    try {
      final store = await ref.read(memoryBookStoreProvider.future);
      await store.renameBook(book.id, name);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('重命名失败：$error')));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MemoryBook book,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除《${book.title}》？'),
        content: Text('将删除这本回忆录和里面的 ${book.pageCount} 张照片，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final store = await ref.read(memoryBookStoreProvider.future);
      await store.deleteBook(book.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  void _openBook(BuildContext context, MemoryBook book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryBookPage(bookId: book.id),
      ),
    );
  }

  void _openComposer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const IllustrationComposerPage(),
      ),
    );
  }

  void _openJob(BuildContext context, IllustrationJob job) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IllustrationComposerPage(
          jobId: job.id,
          initialText: job.text,
          contextLabel: job.label,
        ),
      ),
    );
  }
}

/// The illustration job that is running or just finished, surfaced here so the
/// memory shelf can reach it without going back through the reader.
class _CurrentGenerationCard extends StatelessWidget {
  const _CurrentGenerationCard({
    required this.job,
    required this.onOpen,
    required this.onStop,
    required this.onDismiss,
  });

  final IllustrationJob job;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = job.isRunning;
    final done =
        job.status == IllustrationJobStatus.done && job.result != null;
    final title = running
        ? '插画生成中 · ${job.stage?.label ?? '准备中…'}'
        : done
            ? '插画已生成'
            : '插画生成失败';
    final subtitle = running
        ? '可以先去读，画完会通知你。'
        : done
            ? '还没收进回忆录，打开可以保存。'
            : job.error ?? '';

    return Card(
      key: const Key('memory-current-job'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _thumb(theme, running, done),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (running) ...[
              OutlinedButton(
                key: const Key('memory-current-job-stop'),
                onPressed: onStop,
                child: const Text('停止'),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton.tonal(
              key: const Key('memory-current-job-open'),
              onPressed: onOpen,
              child: Text(running ? '查看进度' : '查看'),
            ),
            IconButton(
              key: const Key('memory-current-job-dismiss'),
              tooltip: '关闭提示',
              onPressed: running ? null : onDismiss,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(ThemeData theme, bool running, bool done) {
    const size = 56.0;
    if (running) {
      return const SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final result = job.result;
    if (done && result != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          result.finalFile,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _icon(theme),
        ),
      );
    }
    return _icon(theme);
  }

  Widget _icon(ThemeData theme) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Icon(
        Icons.error_outline,
        color: theme.colorScheme.error,
      ),
    );
  }
}

class _MemoryBookCard extends StatelessWidget {
  const _MemoryBookCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final MemoryBook book;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cover(context),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: PopupMenuButton<String>(
                        tooltip: '更多',
                        icon: const Icon(
                          Icons.more_horiz,
                          size: 20,
                          color: Colors.white,
                        ),
                        onSelected: (value) {
                          if (value == 'open') onOpen();
                          if (value == 'rename') onRename();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'open', child: Text('打开')),
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${book.pageCount} 张照片',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final path = book.coverPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3E544A), Color(0xFF1D2B25)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.photo_album_outlined,
              color: Color(0xFFD9C7A3),
              size: 34,
            ),
            const SizedBox(height: 12),
            Text(
              book.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: const Color(0xFFEADCC2),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMemoryShelf extends StatelessWidget {
  const _EmptyMemoryShelf({required this.onCreate, required this.onGenerate});

  final VoidCallback onCreate;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 46,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text('还没有回忆录', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '新建一本，把生成的插画一页页收进去。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('生成插画'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建回忆录'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
