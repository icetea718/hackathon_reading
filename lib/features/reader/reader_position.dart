import '../../domain/models/chapter.dart';

class ResumeLocation {
  const ResumeLocation({required this.chapterIndex, required this.fraction});

  final int chapterIndex;
  final double fraction;
}

ResumeLocation locateAnchor(List<Chapter> chapters, int charOffset) {
  if (chapters.isEmpty) {
    return const ResumeLocation(chapterIndex: 0, fraction: 0);
  }
  if (charOffset <= chapters.first.startOffset) {
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
    if (charOffset >= chapter.startOffset && charOffset < chapter.endOffset) {
      final length = chapter.contentText.length;
      final fraction = length == 0
          ? 0.0
          : (charOffset - chapter.startOffset) / length;
      return ResumeLocation(chapterIndex: i, fraction: fraction);
    }
  }

  return ResumeLocation(chapterIndex: chapters.length - 1, fraction: 1);
}

int offsetForPosition(Chapter chapter, double fraction) {
  final clamped = fraction.clamp(0.0, 1.0);
  final offset =
      chapter.startOffset + (clamped * chapter.contentText.length).round();
  return offset > chapter.endOffset ? chapter.endOffset : offset;
}
