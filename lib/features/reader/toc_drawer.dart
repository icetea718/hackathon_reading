import 'package:flutter/material.dart';

import '../../domain/models/chapter.dart';

class TocDrawer extends StatelessWidget {
  const TocDrawer({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<Chapter> chapters;
  final int currentIndex;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView.builder(
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
        ),
      ),
    );
  }
}
