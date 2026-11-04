import 'chapter_paginator.dart';

/// Where the text for an illustration comes from.
enum IllustrationSource {
  page('当前页'),
  nearby('前后页面'),
  chapter('整章');

  const IllustrationSource(this.label);

  final String label;
}

/// The slice of [chapterText] a reader picked for the illustration prompt.
///
/// Page offsets are relative to [chapterText]; without a pagination (or with
/// one built for another layout) the whole chapter is the safe fallback.
String illustrationTextForSource({
  required IllustrationSource source,
  required String chapterText,
  ChapterPagination? pagination,
  required int startPage,
  required int endPage,
}) {
  final full = chapterText.trim();
  if (source == IllustrationSource.chapter || pagination == null) {
    return full;
  }
  final count = pagination.pageCount;
  if (count == 0) return full;

  var first = startPage;
  var last = endPage;
  if (source == IllustrationSource.nearby) {
    first -= 1;
    last += 1;
  }
  first = first.clamp(0, count - 1);
  last = last.clamp(first, count - 1);
  final start = pagination.pageAt(first).start.clamp(0, chapterText.length);
  final end = pagination.pageAt(last).end.clamp(start, chapterText.length);
  final text = chapterText.substring(start, end).trim();
  return text.isEmpty ? full : text;
}
