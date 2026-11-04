import 'package:flutter/material.dart';

import 'home_providers.dart';

class SectionRail extends StatelessWidget {
  const SectionRail({
    super.key,
    required this.activeSection,
    required this.onSelectSection,
    required this.onSettings,
    this.settingsTooltip = '设置',
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
  final String settingsTooltip;
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
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '阅',
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          button(
            key: const Key('rail-bookshelf'),
            tooltip: '书架',
            icon: Icons.menu_book_outlined,
            active: activeSection == AppSection.bookshelf,
            onPressed: () => onSelectSection(AppSection.bookshelf),
          ),
          button(
            key: const Key('rail-companion'),
            tooltip: '陪读',
            icon: Icons.chat_bubble_outline,
            active: activeSection == AppSection.companion,
            onPressed: () => onSelectSection(AppSection.companion),
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
