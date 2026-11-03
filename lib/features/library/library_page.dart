import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/services/book_service.dart';
import '../../domain/services/epub_book_parser.dart';
import 'book_card.dart';

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
  return '导入失败，请稍后重试';
}

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    try {
      final path = await ref.read(filePickerProvider).pickBookFile();
      if (path == null) return;
      final service = await ref.read(bookServiceProvider.future);
      await service.importFile(path);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(importErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(bookListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.add),
            tooltip: '导入',
          ),
        ],
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('还没有书，点右上角导入'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemCount: list.length,
            itemBuilder: (context, index) => BookCard(book: list[index]),
          );
        },
      ),
    );
  }
}
