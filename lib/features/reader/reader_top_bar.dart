import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class ReaderTopBar extends StatelessWidget implements PreferredSizeWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.background,
    required this.foreground,
    required this.pinned,
    this.onTogglePinned,
    required this.bookmarked,
    this.onToggleBookmark,
    this.onOpenAnnotations,
    this.onTranslate,
    this.translationActive = false,
    this.translationBusy = false,
    this.ttsMuted = false,
    this.onToggleTtsMuted,
    required this.onOpenToc,
    this.onOpenCompanion,
    this.onOpenReaderSettings,
    this.onToggleSpread,
    this.doubleSpread = false,
    this.comicMode = false,
  });

  static const double height = 48;

  final String title;
  final Color background;
  final Color foreground;
  final bool pinned;
  final VoidCallback? onTogglePinned;
  final bool bookmarked;
  final VoidCallback? onToggleBookmark;
  final VoidCallback? onOpenAnnotations;
  final VoidCallback? onTranslate;
  final bool translationActive;
  final bool translationBusy;

  /// The master mute, mirrored from the settings page so it can be flipped
  /// without leaving the book.
  final bool ttsMuted;
  final VoidCallback? onToggleTtsMuted;

  final VoidCallback onOpenToc;
  final VoidCallback? onOpenCompanion;
  final VoidCallback? onOpenReaderSettings;
  final VoidCallback? onToggleSpread;
  final bool doubleSpread;
  final bool comicMode;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final accent = background.computeLuminance() < 0.5
        ? AppTheme.darkAccent
        : AppTheme.accent;

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
        child: IconButtonTheme(
          data: const IconButtonThemeData(
            style: ButtonStyle(visualDensity: VisualDensity.compact),
          ),
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
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: foreground),
                  ),
                ),
                if (onToggleSpread != null)
                  IconButton(
                    key: const Key('reader-spread-toggle'),
                    tooltip: doubleSpread ? '双页' : '单页',
                    icon: Icon(
                      doubleSpread
                          ? Icons.auto_stories_outlined
                          : Icons.crop_portrait,
                    ),
                    onPressed: onToggleSpread,
                  ),
                IconButton(
                  tooltip: '目录',
                  icon: const Icon(Icons.menu),
                  onPressed: onOpenToc,
                ),
                IconButton(
                  tooltip: '书签',
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  ),
                  onPressed: onToggleBookmark,
                ),
                IconButton(
                  tooltip: comicMode ? '漫画暂不支持标注' : '标注',
                  icon: const Icon(Icons.format_list_bulleted),
                  onPressed: onOpenAnnotations,
                ),
                if (onTranslate != null)
                  IconButton(
                    key: const Key('reader-translate-button'),
                    tooltip: translationBusy
                        ? '正在翻译…'
                        : translationActive
                        ? '查看原文'
                        : '翻译本章',
                    icon: Icon(
                      Icons.translate,
                      color: translationActive ? accent : null,
                    ),
                    onPressed: translationBusy ? null : onTranslate,
                  ),
                if (onToggleTtsMuted != null)
                  IconButton(
                    key: const Key('reader-tts-mute'),
                    tooltip: ttsMuted ? '取消静音' : '静音朗读',
                    icon: Icon(ttsMuted ? Icons.volume_off : Icons.volume_up),
                    onPressed: onToggleTtsMuted,
                  ),
                IconButton(
                  tooltip: comicMode ? '漫画暂不支持陪读' : '陪读',
                  icon: const Icon(Icons.forum_outlined),
                  onPressed: onOpenCompanion,
                ),
                IconButton(
                  tooltip: comicMode ? '漫画暂不支持设置' : '设置',
                  icon: const Icon(Icons.text_fields),
                  onPressed: onOpenReaderSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
