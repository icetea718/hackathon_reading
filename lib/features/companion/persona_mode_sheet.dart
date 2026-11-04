import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../assistant/persona.dart';

/// Opens the mode chooser and returns the mode the reader picked, or null when
/// the sheet was dismissed. Picking applies the choice and closes immediately.
Future<PersonaMode?> showPersonaModeSheet(BuildContext context) {
  return showModalBottomSheet<PersonaMode>(
    context: context,
    showDragHandle: true,
    builder: (_) => const PersonaModeSheet(),
  );
}

/// The window where the reader decides how the companion talks to them.
class PersonaModeSheet extends ConsumerWidget {
  const PersonaModeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(personaModeProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('陪读模式', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '只换说话的方式，这段对话和读到哪一页都不动。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final mode in PersonaMode.values) ...[
              _ModeCard(
                mode: mode,
                selected: mode == current,
                onTap: () => _pick(context, ref, mode),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Text(
              '两种模式都不替你读，也不直接给答案。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Applies the choice and closes at once.
  ///
  /// The switch is in memory before the pop, so the panel behind the sheet
  /// already shows the new voice; remembering it on disk happens afterwards and
  /// never blocks the tap.
  void _pick(BuildContext context, WidgetRef ref, PersonaMode mode) {
    unawaited(ref.read(personaModeProvider.notifier).select(mode));
    Navigator.of(context).pop(mode);
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final PersonaMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('persona-option-${mode.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          mode.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          modeIcon(mode),
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mode.blurb,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '“${mode.sample}”',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One icon per voice, shared by the pill and the chooser.
IconData modeIcon(PersonaMode mode) => switch (mode) {
      PersonaMode.gentle => Icons.spa_outlined,
      PersonaMode.debate => Icons.bolt_outlined,
    };
