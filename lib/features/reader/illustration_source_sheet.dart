import 'package:flutter/material.dart';

import 'illustration_source.dart';

/// Asks how much of the chapter the illustration prompt should see.
Future<IllustrationSource?> showIllustrationSourceSheet(BuildContext context) {
  return showModalBottomSheet<IllustrationSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      void choose(IllustrationSource source) =>
          Navigator.of(sheetContext).pop(source);

      return SafeArea(
        child: Column(
          key: const Key('illustration-source-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('从哪里取文生图？', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '选中的文字可以直接在正文右键里生成。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              key: const Key('illustration-source-page'),
              leading: const Icon(Icons.crop_portrait),
              title: const Text('当前页'),
              subtitle: const Text('正在看的这一页'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => choose(IllustrationSource.page),
            ),
            ListTile(
              key: const Key('illustration-source-nearby'),
              leading: const Icon(Icons.view_agenda_outlined),
              title: const Text('前后页面'),
              subtitle: const Text('上一页、这一页和下一页一起交给 AI'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => choose(IllustrationSource.nearby),
            ),
            ListTile(
              key: const Key('illustration-source-chapter'),
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('整章'),
              subtitle: const Text('本章全文，适合有完整情节的段落'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => choose(IllustrationSource.chapter),
            ),
          ],
        ),
      );
    },
  );
}
