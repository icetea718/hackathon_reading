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
    this.chapterPage,
    this.chapterPageEnd,
    this.chapterPageCount,
    this.bookPage,
    this.bookPageTotal,
    this.pageStartOffset,
    this.pageEndOffset,
    this.currentPageText = '',
    this.allowSpoilers = false,
    this.bookBrief = '',
    this.companionMemory = '',
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

  /// One-based page the reader is on inside the current chapter.
  final int? chapterPage;

  /// One-based last page of the spread, when two pages are shown at once.
  final int? chapterPageEnd;

  /// Total pages in the current chapter under the current layout.
  final int? chapterPageCount;

  /// One-based page counted across the whole book.
  final int? bookPage;

  /// Total pages in the whole book, when the reader has finished counting.
  final int? bookPageTotal;

  /// Chapter-relative offset where the page (or spread) begins.
  final int? pageStartOffset;

  /// Chapter-relative offset where the page (or spread) ends, exclusive.
  final int? pageEndOffset;

  /// Text of the page (or spread) the reader is looking at right now.
  final String currentPageText;

  /// Whether the reader has opted in to hearing about later content.
  final bool allowSpoilers;

  /// Distilled whole-book preamble assembled before the request.
  final String bookBrief;

  /// Digest of conversations from chapters before [chapterIndex].
  final String companionMemory;

  ReadingContext copyWith({
    String? bookTitle,
    String? author,
    String? chapterTitle,
    String? chapterText,
    String? selectedText,
    String? bookId,
    int? chapterIndex,
    int? chapterCharOffset,
    int? chapterPage,
    int? chapterPageEnd,
    int? chapterPageCount,
    int? bookPage,
    int? bookPageTotal,
    int? pageStartOffset,
    int? pageEndOffset,
    String? currentPageText,
    bool? allowSpoilers,
    String? bookBrief,
    String? companionMemory,
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
      chapterPage: chapterPage ?? this.chapterPage,
      chapterPageEnd: chapterPageEnd ?? this.chapterPageEnd,
      chapterPageCount: chapterPageCount ?? this.chapterPageCount,
      bookPage: bookPage ?? this.bookPage,
      bookPageTotal: bookPageTotal ?? this.bookPageTotal,
      pageStartOffset: pageStartOffset ?? this.pageStartOffset,
      pageEndOffset: pageEndOffset ?? this.pageEndOffset,
      currentPageText: currentPageText ?? this.currentPageText,
      allowSpoilers: allowSpoilers ?? this.allowSpoilers,
      bookBrief: bookBrief ?? this.bookBrief,
      companionMemory: companionMemory ?? this.companionMemory,
    );
  }
}
