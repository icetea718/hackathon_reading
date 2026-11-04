import '../../domain/models/chapter.dart';
import 'chapter_paginator.dart';

class ResumeLocation {
  const ResumeLocation({required this.chapterIndex, required this.fraction});

  final int chapterIndex;
  final double fraction;
}

ResumeLocation locateAnchor(List<Chapter> chapters, int charOffset) {
  if (chapters.isEmpty) {
    return const ResumeLocation(chapterIndex: 0, fraction: 0);
  }
  if (charOffset < chapters.first.startOffset) {
    return const ResumeLocation(chapterIndex: 0, fraction: 0);
  }
  if (charOffset >= chapters.last.endOffset) {
    return ResumeLocation(
      chapterIndex: chapters.length - 1,
      fraction: 1,
    );
  }

  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    if (chapter.endOffset <= chapter.startOffset) continue;
    if (charOffset >= chapter.startOffset && charOffset < chapter.endOffset) {
      final length = chapter.endOffset - chapter.startOffset;
      final fraction = ((charOffset - chapter.startOffset) / length)
          .clamp(0.0, 1.0)
          .toDouble();
      return ResumeLocation(chapterIndex: i, fraction: fraction);
    }
  }

  return ResumeLocation(chapterIndex: chapters.length - 1, fraction: 1);
}

int absoluteOffsetForPageSelection(
  Chapter chapter,
  PageSlice page,
  int localOffset,
) {
  return chapter.startOffset + page.start + localOffset;
}

int offsetForPosition(Chapter chapter, double fraction) {
  final clamped = fraction.clamp(0.0, 1.0);
  final length = chapter.endOffset - chapter.startOffset;
  final offset = chapter.startOffset + (clamped * length).round();
  return offset > chapter.endOffset ? chapter.endOffset : offset;
}

int anchorOffsetForFraction(Chapter chapter, double fraction) {
  final length = chapter.endOffset - chapter.startOffset;
  if (length <= 1) return chapter.startOffset;
  final clamped = fraction.clamp(0.0, 1.0);
  final offset = chapter.startOffset + (clamped * length).round();
  if (offset <= chapter.startOffset) return chapter.startOffset + 1;
  if (offset >= chapter.endOffset) return chapter.endOffset - 1;
  return offset;
}
