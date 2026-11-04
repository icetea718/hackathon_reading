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
    this.onOpenIllustration,
    required this.background,
    required this.foreground,
    required this.accent,
    this.companionEnabled = true,
    this.companionTooltip = '陪读',
    this.elevated = false,
  });

  final bool pinned;
  final VoidCallback onTogglePinned;
  final VoidCallback onBackToLibrary;
  final VoidCallback onOpenCompanion;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenIllustration;
  final Color background;
  final Color foreground;
  final Color accent;
  final bool companionEnabled;
  final String companionTooltip;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return SectionRail(
      activeSection: null,
      onSelectSection: (section) {
        switch (section) {
          case AppSection.bookshelf:
            onBackToLibrary();
          case AppSection.memory:
            break;
          case AppSection.companion:
            onOpenCompanion();
        }
      },
      onSettings: onOpenSettings,
      onIllustration: onOpenIllustration,
      illustrationTooltip: '插画',
      settingsTooltip: '应用设置',
      companionEnabled: companionEnabled,
      companionTooltip: companionTooltip,
      backgroundColor: background,
      foregroundColor: foreground,
      selectedBackgroundColor: accent.withValues(alpha: 0.18),
      selectedForegroundColor: accent,
      elevated: elevated,
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
