import 'package:flutter/material.dart';

import '../../domain/models/annotation.dart';
import '../../domain/models/chapter.dart';

class TocDrawer extends StatelessWidget {
  const TocDrawer({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.currentChapterId,
    required this.bookmarks,
    required this.onSelect,
    required this.onSelectBookmark,
    required this.onDeleteBookmark,
  });

  final List<Chapter> chapters;
  final int currentIndex;
  final String? currentChapterId;
  final List<Annotation> bookmarks;
  final void Function(int index) onSelect;
  final void Function(int anchorStart) onSelectBookmark;
  final void Function(Annotation bookmark) onDeleteBookmark;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: '目录'),
                  Tab(text: '书签'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _chapterList(context),
                    _bookmarkList(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chapterList(BuildContext context) {
    return ListView.builder(
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(chapters[index].title),
          selected: index == currentIndex,
          onTap: () {
            Navigator.of(context).pop();
            onSelect(index);
          },
        );
      },
    );
  }

  Widget _bookmarkList(BuildContext context) {
    if (bookmarks.isEmpty) {
      return const Center(child: Text('还没有书签'));
    }

    final lastEnd = chapters.isEmpty ? 0 : chapters.last.endOffset;
    return ListView.builder(
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        final chapter = _chapterFor(bookmark.chapterId);
        final percent = lastEnd <= 0
            ? 0.0
            : (bookmark.anchorStart / lastEnd).clamp(0.0, 1.0);
        return ListTile(
          title: Text(chapter?.title ?? '未知章节'),
          subtitle: Text('${(percent * 100).round()}%'),
          selected: bookmark.chapterId == currentChapterId,
          onTap: () {
            Navigator.of(context).pop();
            onSelectBookmark(bookmark.anchorStart);
          },
          trailing: IconButton(
            tooltip: '删除书签',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onDeleteBookmark(bookmark),
          ),
        );
      },
    );
  }

  Chapter? _chapterFor(String? chapterId) {
    if (chapterId == null) return null;
    for (final chapter in chapters) {
      if (chapter.id == chapterId) return chapter;
    }
    return null;
  }
}
