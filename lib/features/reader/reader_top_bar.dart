import 'package:flutter/material.dart';

class ReaderTopBar extends StatelessWidget implements PreferredSizeWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.background,
    required this.foreground,
    required this.pinned,
    required this.onTogglePinned,
    required this.bookmarked,
    required this.onToggleBookmark,
    required this.onOpenAnnotations,
    required this.onTranslate,
    required this.onOpenToc,
    required this.onOpenCompanion,
    required this.onOpenReaderSettings,
  });

  static const double height = 48;

  final String title;
  final Color background;
  final Color foreground;
  final bool pinned;
  final VoidCallback onTogglePinned;
  final bool bookmarked;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenAnnotations;
  final VoidCallback onTranslate;
  final VoidCallback onOpenToc;
  final VoidCallback onOpenCompanion;
  final VoidCallback onOpenReaderSettings;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final accent = background.computeLuminance() < 0.5
        ? const Color(0xFF7FA3FF)
        : const Color(0xFF3D6AE0);

    return Material(
      color: background,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: foreground.withValues(alpha: 0.12)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IconTheme(
          data: IconThemeData(color: foreground),
          child: Row(
            children: [
              if (Navigator.of(context).canPop()) const BackButton(),
              IconButton(
                key: const Key('reader-pin-button'),
                tooltip: '固定左栏',
                icon: Icon(
                  Icons.vertical_split_outlined,
                  color: pinned ? accent : foreground,
                ),
                onPressed: onTogglePinned,
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '目录',
                icon: const Icon(Icons.menu),
                onPressed: onOpenToc,
              ),
              IconButton(
                tooltip: '书签',
                icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
                onPressed: onToggleBookmark,
              ),
              IconButton(
                tooltip: '标注',
                icon: const Icon(Icons.format_list_bulleted),
                onPressed: onOpenAnnotations,
              ),
              IconButton(
                tooltip: '翻译本章',
                icon: const Icon(Icons.translate),
                onPressed: onTranslate,
              ),
              IconButton(
                tooltip: '陪读',
                icon: const Icon(Icons.forum_outlined),
                onPressed: onOpenCompanion,
              ),
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.text_fields),
                onPressed: onOpenReaderSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
