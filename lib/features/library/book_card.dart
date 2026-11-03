import 'package:flutter/material.dart';

import '../../domain/models/book.dart';
import 'book_cover.dart';

enum _BookAction { open, addToCategory, distill, delete }

class BookCard extends StatelessWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.onOpen,
    this.percent,
    this.manageMode = false,
    this.selected = false,
    this.onToggleSelected,
    this.onAddToCategory,
    this.onDelete,
    this.onDistill,
  });

  final Book book;
  final double? percent;
  final bool manageMode;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback? onToggleSelected;
  final VoidCallback? onAddToCategory;
  final VoidCallback? onDelete;
  final VoidCallback? onDistill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: manageMode ? () => onToggleSelected?.call() : onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(book: book),
                  if (manageMode)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Checkbox(
                        value: selected,
                        onChanged: (_) => onToggleSelected?.call(),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: PopupMenuButton<_BookAction>(
                      tooltip: '更多',
                      icon: const Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: Colors.white,
                      ),
                      onSelected: (action) => _handleAction(context, action),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _BookAction.open,
                          child: Text('打开'),
                        ),
                        const PopupMenuItem(
                          value: _BookAction.addToCategory,
                          child: Text('添加到分类…'),
                        ),
                        PopupMenuItem(
                          value: _BookAction.distill,
                          enabled: book.format != BookFormat.pdf,
                          child: const Text('蒸馏'),
                        ),
                        const PopupMenuItem(
                          value: _BookAction.delete,
                          child: Text('删除'),
                        ),
                      ],
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
                  const SizedBox(height: 2),
                  Text(
                    book.author.trim().isEmpty ? '未知作者' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (percent == null)
                    Text(
                      '未开始',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(1),
                            child: LinearProgressIndicator(
                              value: percent,
                              minHeight: 2,
                              backgroundColor: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${(percent! * 100).round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, _BookAction action) {
    switch (action) {
      case _BookAction.open:
        onOpen();
      case _BookAction.addToCategory:
        onAddToCategory?.call();
      case _BookAction.distill:
        onDistill?.call();
      case _BookAction.delete:
        _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这本书？'),
        content: Text('将删除《${book.title}》及其本地副本。'),
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
    if (confirmed == true) onDelete?.call();
  }
}
