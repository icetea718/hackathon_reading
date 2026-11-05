import '../distill/distill_digest.dart';
import '../domain/models/book.dart';
import '../domain/models/chapter.dart';
import 'bigrams.dart';

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

  /// Titles listed after the gist-bearing head of the chapter map.
  static const int maxTitleOnlyChapters = 200;

  /// Null when the book is gone from the shelf.
  ///
  /// [includeExcerpts] is false for the tool path: the model fetches原文 itself,
  /// and pre-picked excerpts would let it answer without ever calling a tool.
  /// [briefChars] widens the book brief so the chapter map can list more titles.
  Future<BookContext?> build(
    String bookId, {
    String question = '',
    bool includeExcerpts = true,
    int? briefChars,
  }) async {
    final book = await loadBook(bookId);
    if (book == null) return null;

    final chapters = await loadChapters(bookId);
    final digest = await digests.load(bookId);
    final distilled = digest != null && !digest.isEmpty;

    final brief = _brief(book, chapters, digest, briefChars ?? maxBriefChars);
    final excerpts = includeExcerpts && distilled
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

  String _brief(
    Book book,
    List<Chapter> chapters,
    DistillDigest? digest,
    int maxChars,
  ) {
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

    if (chapters.isEmpty) {
      if (digest != null && digest.cards.isNotEmpty) {
        buffer.writeln('要点：');
        for (final card in digest.cards.take(6)) {
          buffer.writeln(_cardLine(card));
        }
      }
      return _clip(buffer.toString(), maxChars);
    }

    // The marker is reserved before anything else is written: without it the
    // model cannot tell a partial map from a short book, which is exactly what
    // makes it answer "没有写到" wrongly. Quotas then keep the gist rows from
    // eating the digest cards — gists get half of the room, cards the next 40%,
    // and the title-only rows whatever survives after that.
    final reserve = _markerLength(chapters.length) + 1;
    var room = maxChars - reserve - buffer.length;
    if (room < 0) room = 0;
    var listed = 0;
    var titleOnly = 0;

    if (room >= _minMapRoom) {
      // The cards are reserved before the gist rows are written, so a book whose
      // per-chapter gists are long cannot push the key points out of the map.
      final cardLines = digest == null
          ? const <String>[]
          : [for (final card in digest.cards.take(6)) _cardLine(card)];
      var cardNeed = 0;
      for (final line in cardLines) {
        cardNeed += line.length + 1;
      }
      final cardCap = room * 45 ~/ 100;
      final gistStop =
          buffer.length + room - (cardNeed > cardCap ? cardCap : cardNeed);

      buffer.writeln('章节目录：');
      for (final chapter in chapters.take(maxGists)) {
        if (buffer.length >= gistStop) break;
        final gist = digest?.gists[chapter.index] ?? '';
        final tail = gist.isEmpty ? '' : '：${_clip(gist, 60)}';
        buffer.writeln('第 ${chapter.index + 1} 章 ${chapter.title}$tail');
        listed++;
      }

      if (cardLines.isNotEmpty) {
        buffer.writeln('要点：');
        for (final line in cardLines) {
          if (buffer.length + line.length + 1 + reserve > maxChars) break;
          buffer.writeln(line);
        }
      }

      for (final chapter in chapters.skip(listed)) {
        if (titleOnly >= maxTitleOnlyChapters) break;
        final header = titleOnly == 0 ? _titleOnlyHeader.length + 1 : 0;
        final line = '第 ${chapter.index + 1} 章 ${chapter.title}\n';
        if (buffer.length + header + line.length + reserve > maxChars) break;
        if (titleOnly == 0) buffer.writeln(_titleOnlyHeader.trimRight());
        buffer.write(line);
        titleOnly++;
      }
    }

    final shown = listed + titleOnly;
    final marker = shown < chapters.length
        ? '（共 ${chapters.length} 章，此处只列 $shown 章）'
        : '（共 ${chapters.length} 章）';
    if (maxChars <= marker.length + 1) return _clip(marker, maxChars);

    final headRoom = maxChars - marker.length - 1;
    final body = buffer.toString();
    final head = body.length <= headRoom
        ? body
        : '${body.substring(0, headRoom > 1 ? headRoom - 1 : 0)}…';
    return '$head\n$marker';
  }

  static const String _titleOnlyHeader = '其余章节（仅标题）：';

  /// Below this many characters the map is not worth writing at all; the
  /// marker alone still tells the model how much it is missing.
  static const int _minMapRoom = 40;

  static String _cardLine(DistillDigestCard card) {
    final chaptersLabel = card.sourceChapters.isEmpty
        ? ''
        : '（第 ${card.sourceChapters.map((i) => i + 1).join('、')} 章）';
    final quote = card.quote == null ? '' : '｜原文：${_clip(card.quote!, 60)}';
    return '- ${card.title}：${_clip(card.definition, 160)}$quote$chaptersLabel';
  }

  /// Longest marker this book could produce, used to reserve room for it.
  static int _markerLength(int chapterCount) =>
      '（共 $chapterCount 章，此处只列 $chapterCount 章）'.length + 1;

  Future<List<BookExcerpt>> _excerpts(
    String bookId,
    List<Chapter> chapters,
    DistillDigest digest,
    String question,
  ) async {
    final terms = bigrams(question);
    if (terms.isEmpty || chapters.isEmpty) return const [];

    final ranked = chapters
        .map((chapter) {
          final haystack = '${chapter.title}${digest.gists[chapter.index] ?? ''}';
          final score = bigrams(haystack).intersection(terms).length;
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
}
