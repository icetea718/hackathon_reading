import 'package:flutter/material.dart';

import '../../domain/models/annotation.dart';
import '../../domain/models/pdf_outline.dart';

class PdfOutlineDrawer extends StatelessWidget {
  const PdfOutlineDrawer({
    super.key,
    required this.pageCount,
    required this.outline,
    required this.currentPage,
    required this.bookmarks,
    required this.onSelectPage,
    required this.onSelectBookmark,
    required this.onDeleteBookmark,
  });

  final int pageCount;
  final List<PdfOutlineEntry> outline;
  final int currentPage;
  final List<Annotation> bookmarks;
  final void Function(int pageNumber) onSelectPage;
  final void Function(int pageNumber) onSelectBookmark;
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
                    outline.isEmpty ? _pageList() : _outlineList(context),
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

  Widget _outlineList(BuildContext context) {
    return ListView.builder(
      itemCount: outline.length,
      itemBuilder: (context, index) {
        final entry = outline[index];
        return ListTile(
          contentPadding: EdgeInsets.only(
            left: 16 + entry.depth * 16.0,
            right: 16,
          ),
          title: Text(entry.title),
          selected: entry.pageNumber == currentPage,
          onTap: () {
            Navigator.of(context).pop();
            onSelectPage(entry.pageNumber);
          },
        );
      },
    );
  }

  Widget _pageList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('这本书没有内嵌目录，可按页跳转'),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: pageCount,
            itemBuilder: (context, index) {
              final page = index + 1;
              return ListTile(
                title: Text('第 $page 页'),
                selected: page == currentPage,
                onTap: () {
                  Navigator.of(context).pop();
                  onSelectPage(page);
                },
              );
            },
          ),
        ),
      ],
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
        final page = bookmark.anchorStart;
        return ListTile(
          title: Text('第 $page 页'),
          selected: page == currentPage,
          onTap: () {
            Navigator.of(context).pop();
            onSelectBookmark(page);
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
