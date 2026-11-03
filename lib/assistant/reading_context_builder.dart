import 'reading_context.dart';

class ReadingContextBuilder {
  ReadingContextBuilder({this.maxChapterChars = 4000}) {
    if (maxChapterChars <= 0) {
      throw ArgumentError.value(
        maxChapterChars,
        'maxChapterChars',
        'must be positive',
      );
    }
  }

  final int maxChapterChars;

  ReadingContext build({
    required String bookTitle,
    String? author,
    String? chapterTitle,
    String chapterText = '',
    String selectedText = '',
  }) {
    return ReadingContext(
      bookTitle: bookTitle,
      author: author ?? '',
      chapterTitle: chapterTitle ?? '',
      chapterText: _truncate(chapterText),
      selectedText: selectedText,
    );
  }

  String _truncate(String text) {
    if (text.length <= maxChapterChars) return text;
    return text.substring(0, maxChapterChars);
  }
}
