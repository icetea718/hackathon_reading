/// A saved inline illustration belonging to a book.
class BookIllustration {
  const BookIllustration({
    required this.path,
    required this.chapterIndex,
    required this.offset,
    required this.width,
    required this.height,
  });

  final String path;
  final int chapterIndex;

  /// Character offset into the chapter's `contentText`.
  final int offset;

  /// Intrinsic width in pixels.
  final int width;

  /// Intrinsic height in pixels.
  final int height;
}
