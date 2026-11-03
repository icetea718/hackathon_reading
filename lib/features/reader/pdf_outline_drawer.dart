import 'package:flutter/material.dart';

import '../../domain/models/pdf_outline.dart';

class PdfOutlineDrawer extends StatelessWidget {
  const PdfOutlineDrawer({
    super.key,
    required this.pageCount,
    required this.outline,
    required this.currentPage,
    required this.onSelectPage,
  });

  final int pageCount;
  final List<PdfOutlineEntry> outline;
  final int currentPage;
  final void Function(int pageNumber) onSelectPage;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text('目录', style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: outline.isEmpty ? _pageList() : _outlineList(context),
            ),
          ],
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
}
