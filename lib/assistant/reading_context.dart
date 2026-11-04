enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final ChatRole role;
  final String content;
}

class ReadingContext {
  const ReadingContext({
    required this.bookTitle,
    this.author = '',
    this.chapterTitle = '',
    this.chapterText = '',
    this.selectedText = '',
    this.bookId = '',
    this.chapterIndex = 0,
    this.chapterCharOffset,
    this.bookBrief = '',
  });

  final String bookTitle;
  final String author;
  final String chapterTitle;
  final String chapterText;
  final String selectedText;

  /// Book the reader is in; empty when the caller has no library context.
  final String bookId;

  /// Zero-based index of the chapter being read.
  final int chapterIndex;

  /// Character offset of the reader's anchor inside [chapterText].
  final int? chapterCharOffset;

  /// Distilled whole-book preamble assembled before the request.
  final String bookBrief;

  ReadingContext copyWith({
    String? bookTitle,
    String? author,
    String? chapterTitle,
    String? chapterText,
    String? selectedText,
    String? bookId,
    int? chapterIndex,
    int? chapterCharOffset,
    String? bookBrief,
  }) {
    return ReadingContext(
      bookTitle: bookTitle ?? this.bookTitle,
      author: author ?? this.author,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      chapterText: chapterText ?? this.chapterText,
      selectedText: selectedText ?? this.selectedText,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterCharOffset: chapterCharOffset ?? this.chapterCharOffset,
      bookBrief: bookBrief ?? this.bookBrief,
    );
  }
}
