class Chapter {
  const Chapter({
    required this.id,
    required this.bookId,
    required this.index,
    required this.title,
    required this.startOffset,
    required this.endOffset,
    required this.contentText,
  });

  final String id;
  final String bookId;
  final int index;
  final String title;
  final int startOffset;
  final int endOffset;
  final String contentText;
}
