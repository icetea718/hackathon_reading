import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'book_card.dart';

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
          .showSnackBar(SnackBar(content: Text(error.toString())));
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
