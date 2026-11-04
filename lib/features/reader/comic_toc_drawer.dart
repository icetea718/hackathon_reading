import 'package:flutter/material.dart';

import '../../domain/models/annotation.dart';
import '../../domain/models/comic_page.dart';

class ComicTocDrawer extends StatelessWidget {
  const ComicTocDrawer({
    super.key,
    required this.pages,
    required this.currentIndex,
    required this.bookmarks,
    required this.onSelectPage,
    required this.onSelectBookmark,
    required this.onDeleteBookmark,
  });

  final List<ComicPage> pages;
  final int currentIndex;
  final List<Annotation> bookmarks;
  final void Function(int index) onSelectPage;
  final void Function(int page) onSelectBookmark;
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
                    _pageList(context),
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

  Widget _pageList(BuildContext context) {
    return ListView.builder(
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        return ListTile(
          title: Text(page.title ?? '第 ${index + 1} 页'),
          subtitle: page.title == null ? null : Text('第 ${index + 1} 页'),
          selected: index == currentIndex,
          onTap: () {
            Navigator.of(context).pop();
            onSelectPage(index);
          },
        );
      },
    );
  }

  Widget _bookmarkList(BuildContext context) {
    if (bookmarks.isEmpty) {
      return const Center(child: Text('还没有书签'));
    }

    return ListView.builder(
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        final pageIndex = bookmark.anchorStart - 1;
        final title = pageIndex >= 0 && pageIndex < pages.length
            ? pages[pageIndex].title ?? '第 ${bookmark.anchorStart} 页'
            : '第 ${bookmark.anchorStart} 页';
        return ListTile(
          title: Text(title),
          subtitle: Text('第 ${bookmark.anchorStart} 页'),
          selected: pageIndex == currentIndex,
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
}
