import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/book.dart';

/// Lets the reader attach one shelf book to the conversation.
///
/// Returns the picked book id, or null when the sheet was dismissed.
Future<String?> showBookPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _BookPickerSheet(),
  );
}

class _BookPickerSheet extends ConsumerStatefulWidget {
  const _BookPickerSheet();

  @override
  ConsumerState<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends ConsumerState<_BookPickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = ref.watch(bookListProvider).asData?.value ?? const <Book>[];
    final needle = _filter.trim().toLowerCase();
    final matches = needle.isEmpty
        ? books
        : books
            .where((book) =>
                book.title.toLowerCase().contains(needle) ||
                book.author.toLowerCase().contains(needle))
            .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('选择一本书', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              key: const Key('book-filter'),
              decoration: const InputDecoration(
                hintText: '按书名或作者筛选',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: books.isEmpty
                ? _Message(text: '书架里还没有书')
                : matches.isEmpty
                    ? _Message(text: '没有匹配的书')
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final book = matches[index];
                          return ListTile(
                            key: Key('book-option-${book.id}'),
                            leading: const Icon(Icons.menu_book_outlined),
                            title: Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (book.author.isNotEmpty) book.author,
                                book.format.label,
                                if (book.comic) '漫画',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.of(context).pop(book.id),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
