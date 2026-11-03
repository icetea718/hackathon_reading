import 'package:flutter/material.dart';

enum ReaderBackground { light, sepia, dark }

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.fontSize,
    required this.lineHeight,
    required this.background,
    required this.onChanged,
  });

  final double fontSize;
  final double lineHeight;
  final ReaderBackground background;
  final void Function(
    double fontSize,
    double lineHeight,
    ReaderBackground background,
  ) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('阅读设置', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('字号 ${fontSize.round()}'),
          Slider(
            value: fontSize,
            min: 14,
            max: 28,
            divisions: 14,
            label: '${fontSize.round()}',
            onChanged: (value) =>
                onChanged(value, lineHeight, background),
          ),
          Text('行距 ${lineHeight.toStringAsFixed(1)}'),
          Slider(
            value: lineHeight,
            min: 1.2,
            max: 2.0,
            divisions: 8,
            label: lineHeight.toStringAsFixed(1),
            onChanged: (value) =>
                onChanged(fontSize, value, background),
          ),
          const SizedBox(height: 8),
          const Text('背景'),
          const SizedBox(height: 8),
          SegmentedButton<ReaderBackground>(
            segments: const [
              ButtonSegment(
                value: ReaderBackground.light,
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: ReaderBackground.sepia,
                label: Text('米色'),
              ),
              ButtonSegment(
                value: ReaderBackground.dark,
                label: Text('深色'),
              ),
            ],
            selected: {background},
            onSelectionChanged: (selection) =>
                onChanged(fontSize, lineHeight, selection.first),
          ),
        ],
      ),
    );
  }
}
