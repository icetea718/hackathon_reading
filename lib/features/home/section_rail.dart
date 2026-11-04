import 'package:flutter/material.dart';

import 'home_providers.dart';

class SectionRail extends StatelessWidget {
  const SectionRail({
    super.key,
    required this.activeSection,
    required this.onSelectSection,
    required this.onSettings,
    this.onMemory,
    this.memoryTooltip = '回忆录',
    this.onIllustration,
    this.illustrationTooltip = '插画',
    this.settingsTooltip = '设置',
    this.companionEnabled = true,
    this.companionTooltip = '陪读',
    this.leading,
    this.footer,
    this.backgroundColor,
    this.foregroundColor,
    this.selectedBackgroundColor,
    this.selectedForegroundColor,
    this.elevated = false,
  });

  final AppSection? activeSection;
  final ValueChanged<AppSection> onSelectSection;
  final VoidCallback onSettings;
  final VoidCallback? onMemory;
  final String memoryTooltip;
  final VoidCallback? onIllustration;
  final String illustrationTooltip;
  final bool companionEnabled;
  final String companionTooltip;
  final String settingsTooltip;

  /// Replaces the 阅 badge at the top of the rail. The bookshelf shell puts the
  /// 阅/搜 [ModeSwitch] here; every other rail keeps the plain badge.
  final Widget? leading;
  final Widget? footer;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? selectedBackgroundColor;
  final Color? selectedForegroundColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = backgroundColor ?? theme.colorScheme.surface;
    final foreground = foregroundColor ?? theme.colorScheme.onSurfaceVariant;
    final selectedBackground =
        selectedBackgroundColor ?? theme.colorScheme.secondaryContainer;
    final selectedForeground =
        selectedForegroundColor ?? theme.colorScheme.primary;

    final badge = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '阅',
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1,
          fontFamily: 'Source Han Serif SC',
          fontFamilyFallback: const ['Noto Serif CJK SC', 'SimSun', 'Georgia'],
        ),
      ),
    );

    Widget button({
      required Key key,
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
      required bool active,
    }) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: active ? selectedBackground : null,
            foregroundColor: active ? selectedForeground : foreground,
          ),
        ),
      );
    }

    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(4, 0),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          leading ?? badge,
          const SizedBox(height: 10),
          button(
            key: const Key('rail-bookshelf'),
            tooltip: '书架',
            icon: Icons.menu_book_outlined,
            active: activeSection == AppSection.bookshelf,
            onPressed: () => onSelectSection(AppSection.bookshelf),
          ),
          if (onMemory != null)
            button(
              key: const Key('rail-memory'),
              tooltip: memoryTooltip,
              icon: Icons.photo_album_outlined,
              active: activeSection == AppSection.memory,
              onPressed: onMemory,
            ),
          if (onIllustration != null)
            button(
              key: const Key('rail-illustration'),
              tooltip: illustrationTooltip,
              icon: Icons.auto_awesome,
              active: false,
              onPressed: onIllustration,
            ),
          button(
            key: const Key('rail-companion'),
            tooltip: companionTooltip,
            icon: Icons.chat_bubble_outline,
            active: activeSection == AppSection.companion,
            onPressed: companionEnabled
                ? () => onSelectSection(AppSection.companion)
                : null,
          ),
          button(
            key: const Key('rail-add'),
            tooltip: '后续支持自定义分区',
            icon: Icons.add,
            active: false,
            onPressed: null,
          ),
          const Spacer(),
          ?footer,
          button(
            key: const Key('rail-settings'),
            tooltip: settingsTooltip,
            icon: Icons.settings_outlined,
            active: false,
            onPressed: onSettings,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
