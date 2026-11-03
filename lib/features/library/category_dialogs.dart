import 'package:flutter/material.dart';

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
    if (_submitting || _controller.text.trim().isEmpty) return;
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
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
          onPressed: _submitting || _controller.text.trim().isEmpty
              ? null
              : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
