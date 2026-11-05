import 'package:flutter/material.dart';

import 'companion_clip.dart';
import 'companion_skin.dart';

/// Lets the reader swap the character without changing anything else about it.
///
/// Returns the picked skin, or null when the sheet is dismissed.
Future<CompanionSkin?> showCompanionSkinSheet(
  BuildContext context, {
  required CompanionSkin selected,
}) {
  return showModalBottomSheet<CompanionSkin>(
    context: context,
    showDragHandle: true,
    builder: (context) => CompanionSkinSheet(selected: selected),
  );
}

class CompanionSkinSheet extends StatelessWidget {
  const CompanionSkinSheet({super.key, required this.selected});

  final CompanionSkin selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const Key('companion-skin-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('换一个形象', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '说话、气泡、点头像、右键聊天都不变，只换站在书边的人。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final skin in companionSkins) ...[
                  Expanded(
                    child: _SkinCard(
                      skin: skin,
                      selected: skin.id == selected.id,
                      onTap: () => Navigator.of(context).pop(skin),
                    ),
                  ),
                  if (skin != companionSkins.last) const SizedBox(width: 12),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final CompanionSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: Key('companion-skin-${skin.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 92,
              child: AspectRatio(
                aspectRatio: 0.75,
                child: CompanionClipStage(
                  animate: false,
                  idleClip: skin.idleClip,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              skin.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.onPrimaryContainer : null,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
