import 'package:flutter/material.dart';

import '../home/home_providers.dart';
import '../home/section_rail.dart';

class ReaderRail extends StatelessWidget {
  const ReaderRail({
    super.key,
    required this.pinned,
    required this.onTogglePinned,
    required this.onBackToLibrary,
    required this.onOpenCompanion,
    required this.onOpenSettings,
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final bool pinned;
  final VoidCallback onTogglePinned;
  final VoidCallback onBackToLibrary;
  final VoidCallback onOpenCompanion;
  final VoidCallback onOpenSettings;
  final Color background;
  final Color foreground;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SectionRail(
      activeSection: null,
      onSelectSection: (section) {
        switch (section) {
          case AppSection.bookshelf:
            onBackToLibrary();
          case AppSection.companion:
            onOpenCompanion();
        }
      },
      onSettings: onOpenSettings,
      settingsTooltip: '应用设置',
      backgroundColor: background,
      foregroundColor: foreground,
      selectedBackgroundColor: accent.withValues(alpha: 0.18),
      selectedForegroundColor: accent,
      footer: SizedBox(
        width: 48,
        child: TextButton(
          key: const Key('rail-pin-switch'),
          onPressed: onTogglePinned,
          style: TextButton.styleFrom(
            foregroundColor: pinned ? accent : foreground,
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: Text(pinned ? '已固定' : '固定'),
        ),
      ),
    );
  }
}
