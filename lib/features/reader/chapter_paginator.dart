import 'package:flutter/material.dart';

/// A half-open character range `[start, end)` covering one page.
class PageSlice {
  const PageSlice({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;

  bool contains(int offset) => offset >= start && offset < end;
}

/// The page boundaries of a single chapter under one layout.
class ChapterPagination {
  const ChapterPagination({required this.pages, required this.headingText});

  final List<PageSlice> pages;
  final String? headingText;

  int get pageCount => pages.length;

  PageSlice pageAt(int index) => pages[index.clamp(0, pages.length - 1)];

  int pageIndexForOffset(int offset) {
    if (offset <= pages.first.start) return 0;
    for (var i = 0; i < pages.length; i++) {
      if (offset < pages[i].end) return i;
    }
    return pages.length - 1;
  }
}

ChapterPagination paginateChapter({
  required String text,
  required String title,
  required int level,
  required TextStyle baseStyle,
  required double width,
  required double height,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final headingText = matchedHeadingLine(text, title);
  final singlePage = ChapterPagination(
    pages: [PageSlice(start: 0, end: text.length)],
    headingText: headingText,
  );
  if (text.trim().isEmpty) return singlePage;

  final span = TextSpan(
    style: baseStyle,
    children: [
      if (headingText != null)
        TextSpan(
          text: headingText,
          style: headingTextStyle(baseStyle, level),
        ),
      TextSpan(text: text.substring(headingText?.length ?? 0)),
    ],
  );
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout(maxWidth: width);
  final metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) return singlePage;

  final starts = <int>[];
  var previous = 0;
  for (final line in metrics) {
    final probe = Offset(0, line.baseline - line.ascent + line.height / 2);
    final raw = painter.getPositionForOffset(probe).offset;
    var start = raw.clamp(0, text.length);
    if (start < previous) start = previous;
    starts.add(start);
    previous = start;
  }
  starts[0] = 0;

  final breaks = <int>[];
  var used = 0.0;
  var hasLine = false;
  var pageStart = 0;
  for (var i = 0; i < metrics.length; i++) {
    final lineStart = starts[i];
    final lineEnd = i + 1 < starts.length ? starts[i + 1] : text.length;
    final blank = text.substring(lineStart, lineEnd).trim().isEmpty;
    final lineHeight = metrics[i].height;
    if (hasLine &&
        !blank &&
        lineStart > pageStart &&
        used + lineHeight > height + 0.5) {
      breaks.add(lineStart);
      pageStart = lineStart;
      used = 0;
      hasLine = false;
    }
    used += lineHeight;
    hasLine = true;
  }

  final pages = <PageSlice>[];
  var start = 0;
  for (final boundary in breaks) {
    pages.add(PageSlice(start: start, end: boundary));
    start = boundary;
  }
  pages.add(PageSlice(start: start, end: text.length));
  return ChapterPagination(pages: pages, headingText: headingText);
}

TextStyle headingTextStyle(TextStyle base, int level) {
  final nested = level > 1;
  return base.copyWith(
    fontSize: (base.fontSize ?? 18) * (nested ? 1.2 : 1.5),
    fontWeight: nested ? FontWeight.w600 : FontWeight.w700,
    height: nested ? 1.6 : 1.7,
  );
}

String? matchedHeadingLine(String text, String title) {
  final newline = text.indexOf('\n');
  final firstLine = newline == -1 ? text : text.substring(0, newline);
  final key = _headingKey(firstLine);
  if (key.isEmpty || key != _headingKey(title)) return null;
  return firstLine;
}

String _headingKey(String value) {
  return value
      .replaceAll(RegExp(r'\[[^\]]*\]|［[^］]*］|【[^】]*】'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
}
