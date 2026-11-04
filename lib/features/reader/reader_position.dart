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

int bookPageAt({
  required List<int> chapterPageCounts,
  required int chapterIndex,
  required int pageIndex,
}) {
  var cumulative = 0;
  for (var i = 0; i < chapterIndex && i < chapterPageCounts.length; i++) {
    cumulative += chapterPageCounts[i];
  }
  return cumulative + pageIndex + 1;
}

String readingFooterText({
  required int pageIndex,
  int? pageEndIndex,
  required int? chapterPageCount,
  int? bookPageIndex,
  int? bookPageTotal,
}) {
  final chapter = pageEndIndex != null && pageEndIndex > pageIndex
      ? '第 ${pageIndex + 1}–${pageEndIndex + 1} / ${chapterPageCount ?? '…'} 页'
      : '第 ${pageIndex + 1} / ${chapterPageCount ?? '…'} 页';
  return '$chapter · 全书 ${bookPageIndex ?? '…'} / ${bookPageTotal ?? '…'} 页';
}
