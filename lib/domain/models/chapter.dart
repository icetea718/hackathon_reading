class Chapter {
  const Chapter({
    required this.id,
    required this.bookId,
    required this.index,
    required this.title,
    required this.startOffset,
    required this.endOffset,
    required this.contentText,
    this.level = 1,
  });

  final String id;
  final String bookId;
  final int index;
  final String title;
  final int startOffset;
  final int endOffset;
  final String contentText;

  /// 1 for a part/chapter, 2 for a section nested inside it.
  final int level;
}
