class DetectedChapter {
  const DetectedChapter({
    required this.title,
    required this.startOffset,
    required this.endOffset,
    this.level = 1,
  });

  final String title;
  final int startOffset;
  final int endOffset;

  /// 1 for a part/chapter, 2 for a section nested inside it.
  final int level;
}
