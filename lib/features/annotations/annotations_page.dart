import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/annotation.dart';
import '../../domain/models/chapter.dart';
import '../reader/annotation_spans.dart';
import '../reader/reader_providers.dart';

class AnnotationsPage extends ConsumerWidget {
  const AnnotationsPage({
    super.key,
    required this.bookId,
    required this.chapters,
  });

  final String bookId;
  final List<Chapter> chapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotations = ref.watch(readerAnnotationListProvider(bookId));
    return Scaffold(
      appBar: AppBar(title: const Text('标注')),
      body: annotations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('标注加载失败：$error')),
        data: (annotations) {
          if (annotations.isEmpty) {
            return const Center(child: Text('还没有高亮或笔记'));
          }
          return ListView.separated(
            itemCount: annotations.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final annotation = annotations[index];
              return _AnnotationTile(
                annotation: annotation,
                chapterTitle: _chapterTitle(annotation.chapterId),
                onTap: () => Navigator.of(context).pop(annotation.anchorStart),
                onDelete: () => _delete(context, ref, annotation),
              );
            },
          );
        },
      ),
    );
  }

  String _chapterTitle(String? chapterId) {
    for (final chapter in chapters) {
      if (chapter.id == chapterId) return chapter.title;
    }
    return '未知章节';
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Annotation annotation,
  ) async {
    try {
      await ref.read(annotationServiceProvider).delete(annotation.id);
      ref.invalidate(readerAnnotationListProvider(bookId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已删除标注')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('删除标注失败，请重试')));
    }
  }
}

class _AnnotationTile extends StatelessWidget {
  const _AnnotationTile({
    required this.annotation,
    required this.chapterTitle,
    required this.onTap,
    required this.onDelete,
  });

  final Annotation annotation;
  final String chapterTitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isNote = annotation.type == AnnotationType.note;
    final text = annotation.selectedText;
    return ListTile(
      leading: Icon(
        isNote ? Icons.sticky_note_2_outlined : Icons.border_color,
        color: isNote ? noteUnderlineColor : highlightColorFor(annotation.color),
      ),
      title: Text(
        text.isEmpty ? '（没有选中文字）' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chapterTitle),
          if (annotation.noteText.isNotEmpty)
            Text(
              annotation.noteText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      isThreeLine: annotation.noteText.isNotEmpty,
      onTap: onTap,
      trailing: IconButton(
        tooltip: '删除标注',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}
