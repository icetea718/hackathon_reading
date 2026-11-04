import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/category.dart';
import 'category_dialogs.dart';
import 'library_providers.dart';
import 'library_view.dart';

class CategoryPane extends ConsumerWidget {
  const CategoryPane({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) {
    return showCategoryNameDialog(
      context,
      title: '新建分类',
      confirmLabel: '创建',
      onSubmit: (name) async {
        await ref.read(categoryRepositoryProvider).create(name);
      },
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Category category) {
    return showCategoryNameDialog(
      context,
      title: '重命名分类',
      confirmLabel: '保存',
      initialName: category.name,
      onSubmit: (name) async {
        await ref.read(categoryRepositoryProvider).rename(category.id, name);
      },
    );
  }

  Future<void> _addToCategory(
    BuildContext context,
    WidgetRef ref,
    LibraryView view,
    Category category,
    String bookId,
  ) async {
    final already =
        view.categoryIdsByBook[bookId]?.contains(category.id) ?? false;
    if (already) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已经在「${category.name}」中')));
      return;
    }
    try {
      await ref.read(categoryRepositoryProvider).addBook(bookId, category.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('分类更新失败，请重试')));
    }
  }

  Future<void> _createWithBook(
    BuildContext context,
    WidgetRef ref,
    String bookId,
  ) {
    return showCategoryNameDialog(
      context,
      title: '新建分类',
      confirmLabel: '创建',
      onSubmit: (name) async {
        final repository = ref.read(categoryRepositoryProvider);
        final category = await repository.create(name);
        await repository.addBook(bookId, category.id);
      },
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final confirmed = await confirmDeleteCategory(context, category);
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(categoryRepositoryProvider).delete(category.id);
      if (ref.read(selectedCategoryProvider) == category.id) {
        ref.read(selectedCategoryProvider.notifier).select(null);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(libraryViewProvider);
    final categories = ref.watch(categoriesProvider);
    final total = view.value?.allBooks.length ?? 0;

    void select(String? id) =>
        ref.read(selectedCategoryProvider.notifier).select(id);

    return SizedBox(
      width: 208,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('书架', style: theme.textTheme.titleSmall),
                    ),
                    Text(
                      '$total 本',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (categories.hasError)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '分类加载失败',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(categoriesProvider),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: view.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('加载失败：$error')),
                  data: (data) => ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      _CategoryRow(
                        key: const Key('category-row-all'),
                        label: '全部书籍',
                        count: data.allBooks.length,
                        selected: data.effectiveCategoryId == null,
                        onTap: () => select(null),
                      ),
                      for (final summary in data.categories)
                        DragTarget<String>(
                          key: Key('category-drop-${summary.category.id}'),
                          onAcceptWithDetails: (details) => _addToCategory(
                            context,
                            ref,
                            data,
                            summary.category,
                            details.data,
                          ),
                          builder: (context, candidate, rejected) =>
                              _CategoryRow(
                                key: Key('category-row-${summary.category.id}'),
                                label: summary.category.name,
                                count: summary.bookCount,
                                selected:
                                    data.effectiveCategoryId ==
                                    summary.category.id,
                                onTap: () => select(summary.category.id),
                                onRename: () =>
                                    _rename(context, ref, summary.category),
                                onDelete: () =>
                                    _delete(context, ref, summary.category),
                              ),
                        ),
                      _CategoryRow(
                        key: const Key('category-row-uncategorized'),
                        label: '未分类',
                        count: data.uncategorizedCount,
                        selected:
                            data.effectiveCategoryId == uncategorizedCategoryId,
                        onTap: () => select(uncategorizedCategoryId),
                      ),
                      if (data.categories.isEmpty)
                        Padding(
                          key: const Key('category-empty-hint'),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Text(
                            '还没有分类，可拖拽书籍到这里，或点击下方新建',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      DragTarget<String>(
                        key: const Key('category-drop-new'),
                        onAcceptWithDetails: (details) =>
                            _createWithBook(context, ref, details.data),
                        builder: (context, candidate, rejected) => _CategoryRow(
                          key: const Key('category-row-new'),
                          label: '＋ 新建分类',
                          accent: true,
                          onTap: () => _create(context, ref),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    super.key,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
    this.accent = false,
    this.onRename,
    this.onDelete,
  });

  final String label;
  final int? count;
  final bool selected;
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _hovering = false;

  bool get _hasMenu => widget.onRename != null || widget.onDelete != null;

  Future<void> _openMenu(Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
        PopupMenuItem<String>(value: 'delete', child: Text('删除')),
      ],
    );
    if (!mounted) return;
    _run(action);
  }

  void _run(String? action) {
    switch (action) {
      case 'rename':
        widget.onRename?.call();
        return;
      case 'delete':
        widget.onDelete?.call();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ListTile(
        dense: true,
        selected: widget.selected,
        selectedTileColor: theme.colorScheme.secondaryContainer,
        selectedColor: theme.colorScheme.onSurface,
        onTap: widget.onTap,
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.accent
                    ? TextStyle(color: theme.colorScheme.primary)
                    : null,
              ),
            ),
            if (widget.count != null)
              Text(
                '${widget.count}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: _hasMenu
            ? IgnorePointer(
                ignoring: !_hovering,
                child: Opacity(
                  opacity: _hovering ? 1 : 0,
                  child: PopupMenuButton<String>(
                    tooltip: '分类更多',
                    icon: const Icon(Icons.more_horiz, size: 18),
                    padding: EdgeInsets.zero,
                    onSelected: _run,
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Text('重命名'),
                      ),
                      PopupMenuItem<String>(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );

    if (_hasMenu) {
      row = GestureDetector(
        onSecondaryTapDown: (details) => _openMenu(details.globalPosition),
        child: row,
      );
    }
    return row;
  }
}
