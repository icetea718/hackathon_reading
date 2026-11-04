import '../data/repositories/companion_chat_repository.dart';
import '../domain/models/annotation.dart';
import '../domain/models/book.dart';
import '../domain/models/chapter.dart';
import '../domain/models/companion_chat.dart';
import '../features/reader/reader_position.dart';

/// One annotation as the 搜 panel and prompt see it: where it is, what it says.
class BookAnnotationEntry {
  const BookAnnotationEntry({required this.label, required this.text});

  /// Chapter or page the annotation sits on, ready to show as-is.
  final String label;
  final String text;
}

/// Everything the reader left in one book: annotations, companion threads, and
/// the companion digest the 搜 answers should remember.
class BookMemory {
  const BookMemory({
    required this.bookTitle,
    required this.bookmarks,
    required this.highlights,
    required this.notes,
    required this.companionThreads,
    required this.companionDigest,
  });

  static const int maxPromptChars = 1800;
  static const int maxBookmarks = 30;
  static const int maxHighlights = 40;
  static const int maxNotes = 30;

  static const int _maxHighlightChars = 80;
  static const int _maxNoteChars = 100;
  static const int _maxBookmarkChars = 60;

  final String bookTitle;
  final List<BookAnnotationEntry> bookmarks;
  final List<BookAnnotationEntry> highlights;
  final List<BookAnnotationEntry> notes;
  final List<CompanionThread> companionThreads;
  final CompanionDigest companionDigest;

  bool get isEmpty =>
      bookmarks.isEmpty &&
      highlights.isEmpty &&
      notes.isEmpty &&
      companionDigest.text.isEmpty;

  /// The block appended to the 搜 system prompt, or '' when there is nothing
  /// worth telling the model.
  String promptBlock() {
    if (isEmpty) return '';

    final lines = <String>['【读者的标注与陪读记录】'];
    var size = lines.first.length;
    var full = false;

    void add(String line) {
      if (full) return;
      if (size + line.length + 1 > maxPromptChars) {
        full = true;
        return;
      }
      lines.add(line);
      size += line.length + 1;
    }

    void section(String header, List<BookAnnotationEntry> entries) {
      if (entries.isEmpty) return;
      add(header);
      for (final entry in entries) {
        add(entry.text.isEmpty
            ? '- ${entry.label}'
            : '- ${entry.label}：${entry.text}');
      }
    }

    section('书签：', bookmarks.take(maxBookmarks).toList());
    section('高亮：', highlights.take(maxHighlights).toList());
    section('笔记：', notes.take(maxNotes).toList());

    if (companionDigest.text.isNotEmpty) {
      add('【陪读对话摘要】');
      for (final line in companionDigest.text.split('\n')) {
        add(line);
      }
    }
    return lines.join('\n');
  }
}

/// Loads a book's annotations and companion data into a [BookMemory].
class BookMemoryBuilder {
  BookMemoryBuilder({
    required this.loadBook,
    required this.loadChapters,
    required this.loadAnnotations,
    required this.loadThreads,
    required this.loadDigest,
  });

  final Future<Book?> Function(String bookId) loadBook;
  final Future<List<Chapter>> Function(String bookId) loadChapters;
  final Future<List<Annotation>> Function(String bookId) loadAnnotations;
  final Future<List<CompanionThread>> Function(String bookId) loadThreads;

  /// [threadIds] null means the newest companion threads; an empty set means
  /// the reader chose to carry none.
  final Future<CompanionDigest> Function(String bookId, Set<String>? threadIds)
      loadDigest;

  Future<BookMemory?> build(
    String bookId, {
    Set<String>? threadIds,
  }) async {
    final book = await loadBook(bookId);
    if (book == null) return null;

    final chapters = await loadChapters(bookId);
    final annotations = await loadAnnotations(bookId);
    final threads = await loadThreads(bookId);
    final digest = await loadDigest(bookId, threadIds);

    final bookmarks = <BookAnnotationEntry>[];
    final highlights = <BookAnnotationEntry>[];
    final notes = <BookAnnotationEntry>[];
    for (final annotation in annotations) {
      final label = _label(book, chapters, annotation);
      switch (annotation.type) {
        case AnnotationType.bookmark:
          bookmarks.add(
            BookAnnotationEntry(
              label: label,
              text: _clip(annotation.selectedText, BookMemory._maxBookmarkChars),
            ),
          );
        case AnnotationType.highlight:
          highlights.add(
            BookAnnotationEntry(
              label: label,
              text: _clip(
                annotation.selectedText,
                BookMemory._maxHighlightChars,
              ),
            ),
          );
        case AnnotationType.note:
          final text = annotation.noteText.trim().isEmpty
              ? annotation.selectedText
              : annotation.noteText;
          notes.add(
            BookAnnotationEntry(
              label: label,
              text: _clip(text, BookMemory._maxNoteChars),
            ),
          );
      }
    }

    return BookMemory(
      bookTitle: book.title,
      bookmarks: bookmarks,
      highlights: highlights,
      notes: notes,
      companionThreads: threads,
      companionDigest: digest,
    );
  }

  String _label(Book book, List<Chapter> chapters, Annotation annotation) {
    if (book.comic || book.format == BookFormat.pdf) {
      return '第 ${annotation.anchorStart} 页';
    }
    if (annotation.chapterId != null) {
      for (final chapter in chapters) {
        if (chapter.id == annotation.chapterId) {
          return '第 ${chapter.index + 1} 章 ${chapter.title}'.trim();
        }
      }
    }
    if (chapters.isEmpty) return '全书';
    final location = locateAnchor(chapters, annotation.anchorStart);
    final chapter = chapters[location.chapterIndex];
    final percent = (location.fraction * 100).round();
    return '第 ${chapter.index + 1} 章 ${chapter.title} · $percent%'.trim();
  }

  String _clip(String text, int max) {
    final trimmed = text.trim();
    return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
  }
}
