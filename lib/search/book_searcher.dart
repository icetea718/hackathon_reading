import 'dart:math' as math;

import '../distill/distill_digest.dart';
import '../domain/models/chapter.dart';
import 'bigrams.dart';
import 'book_context.dart' show ChapterLoader, ChapterTextLoader;

/// One passage of the book that matched a query.
class BookSnippet {
  const BookSnippet({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.offset,
    required this.score,
    required this.text,
  });

  /// 0-based, as stored in the database.
  final int chapterIndex;
  final String chapterTitle;
  final int offset;
  final int score;
  final String text;

  int get chapterNo => chapterIndex + 1;

  String get label => '第 $chapterNo 章 $chapterTitle'.trim();
}

/// What one search found.
class BookSearch {
  const BookSearch({this.hits = const [], this.truncated = false});

  final List<BookSnippet> hits;

  /// True when the scan budget ran out before the whole book was read.
  final bool truncated;
}

/// Finds passages of a book without reading the whole thing.
///
/// Two stages: rank chapters by matching the query against chapter titles and
/// distilled gists, then slide a window over the few chapters worth reading.
class BookSearcher {
  BookSearcher({
    required this.loadChapters,
    required this.loadChapterText,
    required this.digests,
    this.maxChapters = 8,
    this.window = 200,
    this.stride = 100,
    this.maxScanChars = 400000,
    this.cacheSize = 8,
  });

  final ChapterLoader loadChapters;
  final ChapterTextLoader loadChapterText;
  final DistillDigestSource digests;

  /// How many chapters the coarse stage lets through.
  final int maxChapters;
  final int window;
  final int stride;

  /// Total characters of chapter text one search may read.
  final int maxScanChars;

  /// Chapter texts kept between searches; reading them is the expensive part.
  final int cacheSize;

  final Map<String, String?> _texts = <String, String?>{};

  Future<BookSearch> search(
    String bookId,
    String query, {
    int? chapter,
    int limit = 3,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const BookSearch();

    final chapters = await loadChapters(bookId);
    if (chapters.isEmpty) return const BookSearch();

    final terms = bigrams(trimmed);
    final targets = chapter != null
        ? chapters.where((c) => c.index == chapter).toList()
        : await _pickChapters(bookId, chapters, terms, trimmed);

    final hits = <BookSnippet>[];
    var scanned = 0;
    var truncated = false;

    for (final target in targets) {
      final text = await _text(bookId, target.index);
      if (text == null || text.trim().isEmpty) continue;

      for (var start = 0; start < text.length; start += stride) {
        if (scanned >= maxScanChars) {
          truncated = true;
          break;
        }
        final end = math.min(start + window, text.length);
        final piece = text.substring(start, end);
        scanned += end - start;

        final score = _scoreOf(piece, terms, trimmed);
        if (score <= 0) continue;
        hits.add(
          BookSnippet(
            chapterIndex: target.index,
            chapterTitle: target.title,
            offset: start,
            score: score,
            text: piece,
          ),
        );
      }
      if (truncated) break;
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byChapter = a.chapterIndex.compareTo(b.chapterIndex);
      if (byChapter != 0) return byChapter;
      return a.offset.compareTo(b.offset);
    });

    return BookSearch(
      hits: hits.take(limit).toList(),
      truncated: truncated,
    );
  }

  /// Chapters whose title or gist shares the most with the query. Falls back to
  /// the first few chapters when nothing scores — an undigested book has no
  /// gists, and answering "I found nothing" without reading is worse.
  ///
  /// A one-character query has no bigrams, so every chapter would score zero and
  /// the fallback would silently read only the first [maxChapters] of them; that
  /// case is scored by plain substring count instead and, when nothing matches,
  /// walks the whole map — the scan budget and `truncated` then tell the truth.
  Future<List<Chapter>> _pickChapters(
    String bookId,
    List<Chapter> chapters,
    Set<String> terms,
    String query,
  ) async {
    final digest = await digests.load(bookId);
    final scored = chapters
        .map((chapter) {
          final haystack =
              '${chapter.title}${digest?.gists[chapter.index] ?? ''}';
          return (
            chapter: chapter,
            score: terms.isEmpty
                ? _countOf(haystack, query)
                : bigrams(haystack).intersection(terms).length,
          );
        })
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.chapter.index.compareTo(b.chapter.index);
      });

    final matched = scored.where((entry) => entry.score > 0).toList();
    if (matched.isNotEmpty) {
      return [for (final entry in matched.take(maxChapters)) entry.chapter];
    }
    if (terms.isEmpty) return [for (final entry in scored) entry.chapter];
    return [for (final entry in scored.take(maxChapters)) entry.chapter];
  }

  int _scoreOf(String piece, Set<String> terms, String query) {
    if (terms.isEmpty) return _countOf(piece, query);
    var score = bigrams(piece).intersection(terms).length;
    if (score > 0 && piece.toLowerCase().contains(query.toLowerCase())) {
      // A window holding the question verbatim is worth more than one that just
      // happens to repeat the same two characters.
      score += terms.length;
    }
    return score;
  }

  static int _countOf(String piece, String query) {
    final hay = piece.toLowerCase();
    final needle = query.toLowerCase();
    if (needle.isEmpty) return 0;
    var count = 0;
    var from = hay.indexOf(needle);
    while (from != -1) {
      count++;
      from = hay.indexOf(needle, from + needle.length);
    }
    return count;
  }

  Future<String?> _text(String bookId, int chapterIndex) async {
    final key = '$bookId#$chapterIndex';
    if (_texts.containsKey(key)) {
      final cached = _texts.remove(key);
      _texts[key] = cached;
      return cached;
    }
    final text = await loadChapterText(bookId, chapterIndex);
    _texts[key] = text;
    while (_texts.length > cacheSize) {
      _texts.remove(_texts.keys.first);
    }
    return text;
  }
}
