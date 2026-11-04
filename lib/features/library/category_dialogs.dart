import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/category_repository.dart';
import '../../domain/models/category.dart';

Future<void> showCategoryNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<void> Function(String name) onSubmit,
  String initialName = '',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CategoryNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      onSubmit: onSubmit,
      initialName: initialName,
    ),
  );
}

Future<bool> confirmDeleteCategory(
  BuildContext context,
  Category category,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('删除分类「${category.name}」？'),
      content: const Text('书籍不会被删除，只会变成未分类。'),
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
  return confirmed ?? false;
}

Future<void> showCategoryPickerDialog(
  BuildContext context, {
  required Set<String> bookIds,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CategoryPickerDialog(bookIds: bookIds),
  );
}

class _CategoryPickerDialog extends ConsumerStatefulWidget {
  const _CategoryPickerDialog({required this.bookIds});

  final Set<String> bookIds;

  @override
  ConsumerState<_CategoryPickerDialog> createState() =>
      _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends ConsumerState<_CategoryPickerDialog> {
  Future<void> _apply(Category category, bool? currentValue) async {
    final repository = ref.read(categoryRepositoryProvider);
    try {
      if (currentValue == true) {
        await repository.removeCategoryFromBooks(category.id, widget.bookIds);
      } else {
        for (final bookId in widget.bookIds) {
          await repository.addBook(bookId, category.id);
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('分类更新失败，请重试')));
    }
  }

  Future<void> _createAndAdd() async {
    await showCategoryNameDialog(
      context,
      title: '新建分类',
      confirmLabel: '创建',
      onSubmit: (name) async {
        final repository = ref.read(categoryRepositoryProvider);
        final category = await repository.create(name);
        for (final bookId in widget.bookIds) {
          await repository.addBook(bookId, category.id);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final memberships = ref.watch(bookCategoryMembershipsProvider);
    final list = categories.value ?? const <Category>[];

    final selectedByCategory = <String, int>{};
    for (final row in memberships.value ?? const <BookCategoryRecord>[]) {
      if (!widget.bookIds.contains(row.bookId)) continue;
      selectedByCategory[row.categoryId] =
          (selectedByCategory[row.categoryId] ?? 0) + 1;
    }

    final total = widget.bookIds.length;
    bool? valueFor(Category category) {
      final count = selectedByCategory[category.id] ?? 0;
      if (count == 0) return false;
      return count == total ? true : null;
    }

    return AlertDialog(
      title: const Text('添加到分类'),
      content: SizedBox(
        width: 320,
        child: categories.hasError
            ? const Text('分类加载失败')
            : list.isEmpty
            ? const Text('还没有分类，先新建一个吧')
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final category in list)
                      InkWell(
                        onTap: () => _apply(category, valueFor(category)),
                        child: Row(
                          children: [
                            Checkbox(
                              key: Key('picker-checkbox-${category.id}'),
                              value: valueFor(category),
                              tristate: true,
                              onChanged: (_) =>
                                  _apply(category, valueFor(category)),
                            ),
                            Expanded(child: Text(category.name)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('category-picker-new'),
          onPressed: _createAndAdd,
          child: const Text('＋ 新建分类…'),
        ),
        TextButton(
          key: const Key('category-picker-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.onSubmit,
    required this.initialName,
  });

  final String title;
  final String confirmLabel;
  final Future<void> Function(String name) onSubmit;
  final String initialName;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _controller;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final trimmed = _controller.text.trim();
    if (_submitting || trimmed.isEmpty || trimmed.length > 20) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_controller.text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on InvalidCategoryNameException {
      _fail('名称需为 1–20 个字符');
    } on DuplicateCategoryException {
      _fail('已有同名分类');
    } catch (_) {
      _fail('操作失败，请重试');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _submitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = _controller.text.trim();
    final lengthValid = trimmed.isNotEmpty && trimmed.length <= 20;
    final message =
        _error ?? (trimmed.length > 20 ? '名称需为 1–20 个字符' : null);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('category-name-field'),
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '分类名称'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('category-name-confirm'),
          onPressed: _submitting || !lengthValid ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
