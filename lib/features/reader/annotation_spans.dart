import 'package:flutter/material.dart';

import '../../domain/models/annotation.dart';

const highlightColors = <String, Color>{
  'yellow': Color(0xFFFFF59D),
  'green': Color(0xFFC8E6C9),
  'pink': Color(0xFFF8BBD0),
};

const highlightColorLabels = <String, String>{
  'yellow': '黄色',
  'green': '绿色',
  'pink': '粉色',
};

const noteUnderlineColor = Color(0xFFF57F17);

Color highlightColorFor(String? name) =>
    highlightColors[name] ?? highlightColors['yellow']!;

List<InlineSpan> buildAnnotationSpans({
  required String text,
  required int chapterStart,
  required List<Annotation> annotations,
  required TextStyle baseStyle,
}) {
  final ranges = <_AnnotatedRange>[];
  for (final annotation in annotations) {
    if (annotation.type != AnnotationType.highlight &&
        annotation.type != AnnotationType.note) {
      continue;
    }
    final end = annotation.anchorEnd;
    if (end == null) continue;
    final start = (annotation.anchorStart - chapterStart).clamp(0, text.length);
    final clippedEnd = (end - chapterStart).clamp(0, text.length);
    if (clippedEnd <= start) continue;
    ranges.add(_AnnotatedRange(start, clippedEnd, annotation));
  }

  ranges.sort((a, b) {
    if (a.start != b.start) return a.start.compareTo(b.start);
    return b.end.compareTo(a.end);
  });

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final range in ranges) {
    final start = range.start < cursor ? cursor : range.start;
    if (range.end <= start) continue;
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start), style: baseStyle));
    }
    spans.add(TextSpan(
      text: text.substring(start, range.end),
      style: _styleFor(range.annotation, baseStyle),
    ));
    cursor = range.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  if (spans.isEmpty) {
    spans.add(TextSpan(text: text, style: baseStyle));
  }
  return spans;
}

TextStyle _styleFor(Annotation annotation, TextStyle baseStyle) {
  return switch (annotation.type) {
    AnnotationType.highlight => baseStyle.copyWith(
        backgroundColor: highlightColorFor(annotation.color),
        color: const Color(0xFF1B1B1B),
      ),
    AnnotationType.note => baseStyle.copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: noteUnderlineColor,
      ),
    AnnotationType.bookmark => baseStyle,
  };
}

class _AnnotatedRange {
  const _AnnotatedRange(this.start, this.end, this.annotation);

  final int start;
  final int end;
  final Annotation annotation;
}
