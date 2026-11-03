import 'dart:math' as math;

import '../domain/models/chapter.dart';

/// A contiguous slice of one reading chapter that fits a single LLM call.
class DistillSegment {
  const DistillSegment({
    required this.key,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.charStartInChapter,
    required this.charEndInChapter,
    required this.text,
  });

  final String key;
  final int chapterIndex;
  final String chapterTitle;
  final int charStartInChapter;
  final int charEndInChapter;
  final String text;

  int get length => text.length;
}

/// Consecutive segments summarised together in one reduce call.
class DistillPart {
  const DistillPart({
    required this.key,
    required this.segments,
    required this.chapterIndexes,
  });

  final String key;
  final List<DistillSegment> segments;
  final List<int> chapterIndexes;

  int get charCount => segments.fold<int>(0, (sum, s) => sum + s.length);
}

class DistillPlan {
  const DistillPlan({required this.segments, required this.parts});

  final List<DistillSegment> segments;
  final List<DistillPart> parts;
}

class DistillPlanner {
  DistillPlanner({
    this.maxSegmentChars = 6000,
    this.maxPartChars = 60000,
    this.minChaptersPerPart = 2,
  });

  final int maxSegmentChars;
  final int maxPartChars;
  final int minChaptersPerPart;

  DistillPlan plan(List<Chapter> chapters) {
    final segments = <DistillSegment>[];
    for (final chapter in chapters) {
      segments.addAll(_segmentChapter(chapter, segments.length));
    }
    return DistillPlan(
      segments: segments,
      parts: _group(segments),
    );
  }

  List<DistillSegment> _segmentChapter(Chapter chapter, int keyOffset) {
    final text = chapter.contentText;
    final out = <DistillSegment>[];
    var start = 0;

    while (start < text.length) {
      final limit = math.min(start + maxSegmentChars, text.length);
      var end = limit;
      if (limit < text.length) {
        final newline = text.lastIndexOf('\n', limit - 1);
        if (newline > start) end = newline + 1;
      }

      var from = start;
      while (from < end && _isWhitespace(text.codeUnitAt(from))) {
        from++;
      }
      final chunk = text.substring(from, end);
      if (chunk.trim().isNotEmpty) {
        out.add(
          DistillSegment(
            key: _key('seg', keyOffset + out.length),
            chapterIndex: chapter.index,
            chapterTitle: chapter.title,
            charStartInChapter: from,
            charEndInChapter: end,
            text: chunk,
          ),
        );
      }
      start = end;
    }
    return out;
  }

  List<DistillPart> _group(List<DistillSegment> segments) {
    final byChapter = <int, List<DistillSegment>>{};
    for (final segment in segments) {
      byChapter.putIfAbsent(segment.chapterIndex, () => []).add(segment);
    }

    final groups = <List<int>>[];
    final sizes = <int>[];
    for (final entry in byChapter.entries) {
      final chars = entry.value.fold<int>(0, (sum, s) => sum + s.length);
      if (groups.isNotEmpty &&
          sizes.last + chars <= maxPartChars) {
        groups.last.add(entry.key);
        sizes[sizes.length - 1] += chars;
      } else {
        groups.add([entry.key]);
        sizes.add(chars);
      }
    }

    while (groups.length > 1) {
      final last = groups.last;
      if (last.length >= minChaptersPerPart) break;
      final mergedSize = sizes[sizes.length - 2] + sizes.last;
      if (mergedSize > maxPartChars) break;
      groups[groups.length - 2].addAll(last);
      sizes[sizes.length - 2] = mergedSize;
      groups.removeLast();
      sizes.removeLast();
    }

    final parts = <DistillPart>[];
    for (var i = 0; i < groups.length; i++) {
      final chapterIndexes = groups[i];
      final partSegments = [
        for (final index in chapterIndexes) ...byChapter[index]!,
      ];
      parts.add(
        DistillPart(
          key: _key('part', i, width: 2),
          segments: partSegments,
          chapterIndexes: chapterIndexes,
        ),
      );
    }
    return parts;
  }

  String _key(String prefix, int index, {int width = 4}) =>
      '$prefix-${index.toString().padLeft(width, '0')}';

  bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;
}
