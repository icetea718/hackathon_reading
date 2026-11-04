import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/book.dart';
import '../../domain/services/book_service.dart';
import '../../domain/services/epub_book_parser.dart';
import '../distill/distill_page.dart';
import '../reader/pdf_reader_page.dart';
import '../reader/reader_page.dart';
import 'book_grid.dart';
import 'category_dialogs.dart';
import 'library_providers.dart';
import 'library_view.dart';
import 'manage_bar.dart';

String importErrorMessage(Object error) {
  if (error is UnsupportedBookFormatException) {
    return '不支持的文件格式，请选择 EPUB、TXT 或 PDF';
  }
  if (error is EmptyBookException) {
    return '文件内容为空，无法导入';
  }
  if (error is EpubParseException) {
    return '文件无法解析，可能已损坏';
  }
  if (error is DuplicateBookException) {
    return '这本书已经在书架中';
  }
  return '导入失败，请稍后重试';
}

class BookshelfView extends ConsumerStatefulWidget {
  const BookshelfView({super.key});

  @override
  ConsumerState<BookshelfView> createState() => _BookshelfViewState();
}

class _BookshelfViewState extends ConsumerState<BookshelfView> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    try {
      final path = await ref.read(filePickerProvider).pickBookFile();
      if (path == null) return;
      final service = await ref.read(bookServiceProvider.future);
      await service.importFile(path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(importErrorMessage(error))));
    }
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => book.format == BookFormat.pdf
            ? PdfReaderPage(bookId: book.id)
            : ReaderPage(bookId: book.id),
      ),
    );
  }

  void _toggleBook(Book book) {
    ref.read(selectedBookIdsProvider.notifier).toggle(book.id);
  }

  Future<void> _deleteBook(Book book) async {
    try {
      final service = await ref.read(bookServiceProvider.future);
      await service.deleteBook(book);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
    }
  }

  void _clearSearch() {
    _search.clear();
    ref.read(searchQueryProvider.notifier).setQuery('');
  }

  void _exitManage() {
    ref.read(manageModeProvider.notifier).setEnabled(false);
    ref.read(selectedBookIdsProvider.notifier).clear();
  }

  void _toggleManage(bool current) {
    ref.read(manageModeProvider.notifier).setEnabled(!current);
    ref.read(selectedBookIdsProvider.notifier).clear();
  }

  Future<void> _removeFromCurrentCategory() async {
    final categoryId = ref.read(selectedCategoryProvider);
    final ids = ref.read(selectedBookIdsProvider);
    if (categoryId == null ||
        categoryId == uncategorizedCategoryId ||
        ids.isEmpty) {
      return;
    }
    try {
      await ref
          .read(categoryRepositoryProvider)
          .removeCategoryFromBooks(categoryId, ids);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('分类更新失败，请重试')));
    }
  }

  Future<void> _deleteSelected() async {
    final ids = ref.read(selectedBookIdsProvider);
    final books = (ref.read(libraryViewProvider).value?.allBooks ?? const [])
        .where((book) => ids.contains(book.id))
        .toList();
    if (books.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除选中的 ${books.length} 本书？'),
        content: const Text('书籍将从书架中移除，本地副本也会删除。'),
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
    if (confirmed != true) return;

    try {
      final service = await ref.read(bookServiceProvider.future);
      for (final book in books) {
        await service.deleteBook(book);
      }
      if (!mounted) return;
      _exitManage();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(libraryViewProvider);
    final manageMode = ref.watch(manageModeProvider);
    final selectedIds = ref.watch(selectedBookIdsProvider);
    final query = ref.watch(searchQueryProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (ref.read(manageModeProvider)) _exitManage();
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('search-field'),
                      controller: _search,
                      onChanged: (value) => ref
                          .read(searchQueryProvider.notifier)
                          .setQuery(value),
                      decoration: const InputDecoration(
                        hintText: '搜索书名、作者…',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => _toggleManage(manageMode),
                    child: const Text('管理'),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '导入',
                    child: FilledButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.add),
                      label: const Text('导入'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: view.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('加载失败：$error')),
                data: (data) {
                  if (data.allBooks.isEmpty) {
                    return _EmptyShelf(onImport: _import);
                  }
                  if (data.visibleBooks.isEmpty) {
                    if (query.trim().isNotEmpty) {
                      return _Message(
                        message: '没有找到匹配的书',
                        action: TextButton(
                          onPressed: _clearSearch,
                          child: const Text('清空搜索'),
                        ),
                      );
                    }
                    return const _Message(message: '这个分类还没有书');
                  }
                  return BookGrid(
                    books: data.visibleBooks,
                    progressByBook: data.progressByBook,
                    manageMode: manageMode,
                    selectedBookIds: selectedIds,
                    onOpen: _openBook,
                    onToggleSelected: _toggleBook,
                    onAddToCategory: (book) => showCategoryPickerDialog(
                      context,
                      ref,
                      bookIds: {book.id},
                    ),
                    onDelete: _deleteBook,
                    onDistill: (book) => openDistillPage(context, book.id),
                  );
                },
              ),
            ),
            ManageBar(
              onAddToCategory: () => showCategoryPickerDialog(
                context,
                ref,
                bookIds: ref.read(selectedBookIdsProvider),
              ),
              onRemoveFromCategory: _removeFromCurrentCategory,
              onDelete: _deleteSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('还没有书', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('导入第一本书'),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) const SizedBox(height: 8),
          ?action,
        ],
      ),
    );
  }
}
