import 'package:flutter/material.dart';

import '../../search/search_step.dart';

/// What the assistant did before it answered.
///
/// Collapsed it is a single line — "检索 2 次 · 第 3、7、12 章"; tapped it lists
/// every step with how long it took. While the answer is still streaming it
/// shows the step in progress instead, so a slow book search looks like work
/// rather than like a hang.
class StepsBar extends StatefulWidget {
  const StepsBar({super.key, required this.steps, required this.streaming});

  final List<SearchStep> steps;
  final bool streaming;

  @override
  State<StepsBar> createState() => _StepsBarState();
}

class _StepsBarState extends State<StepsBar> {
  bool _open = false;

  List<SearchStep> get _work =>
      widget.steps.where((step) => step.tool != 'notice').toList();

  List<SearchStep> get _notices =>
      widget.steps.where((step) => step.tool == 'notice').toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final work = _work;
    final notices = _notices;

    if (widget.streaming) {
      final last = widget.steps.isEmpty ? null : widget.steps.last;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                last?.summary ?? '正在判断要不要翻书…',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (work.isEmpty && notices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final notice in notices) _NoticeLine(step: notice),
        if (work.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  key: const Key('steps-bar-toggle'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.travel_explore,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _summaryLine(work),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Icon(
                          _open ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final step in work)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    step.summary,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                Text(
                                  '${step.ms} ms',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

const int _maxListedChapters = 6;

String _summaryLine(List<SearchStep> work) {
  final chapters = <int>{for (final step in work) ...step.chapters}.toList()
    ..sort();
  final buffer = StringBuffer('检索 ${work.length} 次');
  if (chapters.isNotEmpty) {
    final head = chapters.take(_maxListedChapters).join('、');
    final tail = chapters.length > _maxListedChapters ? '… ' : ' ';
    buffer.write(' · 第 $head$tail章');
  }
  return buffer.toString();
}

class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.step});

  final SearchStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              step.summary,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
