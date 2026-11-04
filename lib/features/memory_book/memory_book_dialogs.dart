import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../memory_book/memory_book_models.dart';
import 'memory_book_providers.dart';

Future<String?> promptMemoryBookName(
  BuildContext context, {
  String title = '新建回忆录',
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _MemoryBookNameDialog(title: title, initial: initial),
  );
}

/// The controller lives with the dialog so it is only disposed once the
/// closing animation has finished rendering the field.
class _MemoryBookNameDialog extends StatefulWidget {
  const _MemoryBookNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_MemoryBookNameDialog> createState() => _MemoryBookNameDialogState();
}

class _MemoryBookNameDialogState extends State<_MemoryBookNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(
          labelText: '名字',
          hintText: '例如：雪夜站台',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial.isEmpty ? '创建' : '保存'),
        ),
      ],
    );
  }
}

Future<String?> pickMemoryBookDialog(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
}) {
  return _pickBook(
    context,
    ref,
    title: '保存到哪本回忆录？',
    selectedId: selectedId,
  );
}

Future<String?> pickMoveTargetDialog(
  BuildContext context,
  WidgetRef ref, {
  required String sourceBookId,
}) {
  return _pickBook(
    context,
    ref,
    title: '移动到哪本回忆录？',
    excludeId: sourceBookId,
  );
}

Future<String?> _pickBook(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  String? selectedId,
  String? excludeId,
}) async {
  final all = ref.read(memoryBookListProvider).value ?? const <MemoryBook>[];
  final books = all.where((book) => book.id != excludeId).toList();

  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return SimpleDialog(
        title: Text(title),
        children: [
          if (books.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text('还没有回忆录，先新建一本。'),
            ),
          for (final book in books)
            ListTile(
              leading: Icon(
                book.id == selectedId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${book.pageCount} 张照片'),
              onTap: () => Navigator.of(dialogContext).pop(book.id),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建回忆录…'),
            onTap: () => Navigator.of(dialogContext).pop('__new__'),
          ),
        ],
      );
    },
  );
  if (choice == null) return null;
  if (choice != '__new__') return choice;

  if (!context.mounted) return null;
  final name = await promptMemoryBookName(context);
  if (name == null) return null;
  final store = await ref.read(memoryBookStoreProvider.future);
  final book = await store.createBook(name);
  return book.id;
}
