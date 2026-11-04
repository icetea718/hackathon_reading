import '../distill/distill_digest.dart';
import '../domain/models/book.dart';
import '../domain/models/chapter.dart';

typedef BookLoader = Future<Book?> Function(String bookId);
typedef ChapterLoader = Future<List<Chapter>> Function(String bookId);
typedef ChapterTextLoader = Future<String?> Function(
  String bookId,
  int chapterIndex,
);

/// A slice of the book's own text, shown to the model as quotable evidence.
class BookExcerpt {
  const BookExcerpt({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.text,
  });

  final int chapterIndex;
  final String chapterTitle;
  final String text;

  String get label => '第 ${chapterIndex + 1} 章 $chapterTitle'.trim();
}

/// Everything the 搜 shell knows about the book the reader picked.
class BookContext {
  const BookContext({
    required this.bookId,
    required this.title,
    required this.author,
    required this.brief,
    this.excerpts = const [],
    this.distilled = false,
  });

  final String bookId;
  final String title;
  final String author;

  /// Whole-book summary plus the chapter map and key points. Written for a
  /// prompt, not for the screen.
  final String brief;
  final List<BookExcerpt> excerpts;

  /// False when the book was never distilled: [brief] then only has titles.
  final bool distilled;

  String get displayTitle => author.isEmpty ? '《$title》' : '《$title》$author';
}

/// Turns a distilled book into a prompt-sized knowledge card, plus the couple
/// of original passages that look most relevant to the current question.
class BookContextBuilder {
  BookContextBuilder({
    required this.loadBook,
    required this.loadChapters,
    required this.loadChapterText,
    required this.digests,
    this.maxBriefChars = 2400,
    this.maxExcerpts = 2,
    this.maxExcerptChars = 1200,
    this.maxGists = 40,
  });

  final BookLoader loadBook;
  final ChapterLoader loadChapters;
  final ChapterTextLoader loadChapterText;
  final DistillDigestSource digests;

  final int maxBriefChars;
  final int maxExcerpts;
  final int maxExcerptChars;
  final int maxGists;

  /// Null when the book is gone from the shelf.
  Future<BookContext?> build(String bookId, {String question = ''}) async {
    final book = await loadBook(bookId);
    if (book == null) return null;

    final chapters = await loadChapters(bookId);
    final digest = await digests.load(bookId);
    final distilled = digest != null && !digest.isEmpty;

    final brief = _brief(book, chapters, digest);
    final excerpts = distilled
        ? await _excerpts(bookId, chapters, digest, question)
        : const <BookExcerpt>[];

    return BookContext(
      bookId: book.id,
      title: book.title,
      author: book.author,
      brief: brief,
      excerpts: excerpts,
      distilled: distilled,
    );
  }

  String _brief(Book book, List<Chapter> chapters, DistillDigest? digest) {
    final buffer = StringBuffer('《${book.title}》');
    if (book.author.isNotEmpty) buffer.write(' ${book.author}');
    buffer.writeln();

    if (digest != null && !digest.isEmpty) {
      if (digest.oneLiner.isNotEmpty) buffer.writeln('一句话：${digest.oneLiner}');
      if (digest.synopsis.isNotEmpty) {
        buffer.writeln('梗概：${_clip(digest.synopsis, 400)}');
      }
      if (digest.themes.isNotEmpty) {
        buffer.writeln('主题：${digest.themes.take(5).join('、')}');
      }
    } else {
      buffer.writeln('（这本书还没有蒸馏，只有章节标题可用。）');
    }

    if (chapters.isNotEmpty) {
      buffer.writeln('章节目录：');
      final shown = chapters.take(maxGists);
      for (final chapter in shown) {
        final gist = digest?.gists[chapter.index] ?? '';
        final tail = gist.isEmpty ? '' : '：${_clip(gist, 60)}';
        buffer.writeln('第 ${chapter.index + 1} 章 ${chapter.title}$tail');
      }
      if (chapters.length > shown.length) {
        buffer.writeln('…（共 ${chapters.length} 章）');
      }
    }

    if (digest != null && digest.cards.isNotEmpty) {
      buffer.writeln('要点：');
      for (final card in digest.cards.take(6)) {
        final chaptersLabel = card.sourceChapters.isEmpty
            ? ''
            : '（第 ${card.sourceChapters.map((i) => i + 1).join('、')} 章）';
        final quote = card.quote == null ? '' : '｜原文：${_clip(card.quote!, 60)}';
        buffer.writeln(
          '- ${card.title}：${_clip(card.definition, 160)}$quote$chaptersLabel',
        );
      }
    }

    return _clip(buffer.toString(), maxBriefChars);
  }

  Future<List<BookExcerpt>> _excerpts(
    String bookId,
    List<Chapter> chapters,
    DistillDigest digest,
    String question,
  ) async {
    final terms = _bigrams(question);
    if (terms.isEmpty || chapters.isEmpty) return const [];

    final ranked = chapters
        .map((chapter) {
          final haystack = '${chapter.title}${digest.gists[chapter.index] ?? ''}';
          final score = _bigrams(haystack).intersection(terms).length;
          return (chapter: chapter, score: score);
        })
        .where((entry) => entry.score > 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.chapter.index.compareTo(b.chapter.index);
      });

    final picked = <BookExcerpt>[];
    for (final entry in ranked.take(maxExcerpts)) {
      final text = await loadChapterText(bookId, entry.chapter.index);
      if (text == null || text.trim().isEmpty) continue;
      picked.add(
        BookExcerpt(
          chapterIndex: entry.chapter.index,
          chapterTitle: entry.chapter.title,
          text: _clip(text.trim(), maxExcerptChars),
        ),
      );
    }
    return picked;
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  static Set<String> _bigrams(String text) {
    final chars = text
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]'), '')
        .toLowerCase()
        .runes
        .toList();
    final grams = <String>{};
    for (var i = 0; i + 1 < chars.length; i++) {
      grams.add(String.fromCharCodes([chars[i], chars[i + 1]]));
    }
    return grams;
  }
}
