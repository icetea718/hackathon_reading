import 'package:flutter/material.dart';

import '../../domain/models/book_illustration.dart';
import '../../domain/models/chapter.dart';

const double kIllustrationGap = 8.0;

/// An illustration laid out on a page, with display dimensions in logical px.
class PageIllustration {
  const PageIllustration({
    required this.path,
    required this.offset,
    required this.width,
    required this.height,
    required this.gap,
  });

  final String path;

  /// Placement offset (the start of the line the image is anchored to).
  final int offset;
  final double width;
  final double height;
  final double gap;

  double get blockHeight => height + gap * 2;
}

/// A half-open character range `[start, end)` covering one page.
class PageSlice {
  const PageSlice({
    required this.start,
    required this.end,
    this.images = const [],
  });

  final int start;
  final int end;
  final List<PageIllustration> images;

  int get length => end - start;

  bool contains(int offset) => offset >= start && offset < end;
}

/// A run of selectable text between illustrations on the same page.
class PageTextFragment {
  const PageTextFragment({required this.start, required this.end});

  final int start;
  final int end;

  PageSlice get slice => PageSlice(start: start, end: end);
}

List<PageTextFragment> pageTextFragments(PageSlice page) {
  final bounds = <int>{page.start, page.end};
  for (final image in page.images) {
    bounds.add(image.offset.clamp(page.start, page.end));
  }
  final sorted = bounds.toList()..sort();
  return [
    for (var i = 0; i + 1 < sorted.length; i++)
      if (sorted[i] < sorted[i + 1])
        PageTextFragment(start: sorted[i], end: sorted[i + 1]),
  ];
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
      final page = pages[i];
      if (page.start == page.end) {
        if (offset == page.start) return i;
        continue;
      }
      if (offset < page.end) return i;
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
  List<BookIllustration> illustrations = const [],
}) {
  final headingText = matchedHeadingLine(text, title);
  final singlePage = ChapterPagination(
    pages: [PageSlice(start: 0, end: text.length)],
    headingText: headingText,
  );
  if (text.trim().isEmpty && illustrations.isEmpty) return singlePage;

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
  if (metrics.isEmpty && illustrations.isEmpty) return singlePage;

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
  if (starts.isNotEmpty) starts[0] = 0;

  final placed = _placeIllustrations(
    text: text,
    starts: starts,
    lineCount: metrics.length,
    columnWidth: width,
    pageHeight: height,
    illustrations: illustrations,
  );

  final pages = <PageSlice>[];
  var pageStart = 0;
  var used = 0.0;
  var hasItem = false;
  var pageHasImage = false;
  var pageImages = <PageIllustration>[];

  void cutAt(int boundary) {
    pages.add(PageSlice(
      start: pageStart,
      end: boundary,
      images: List.unmodifiable(pageImages),
    ));
    pageStart = boundary;
    used = 0;
    hasItem = false;
    pageHasImage = false;
    pageImages = [];
  }

  void addImage(PageIllustration image) {
    if (hasItem && used + image.blockHeight > height + 0.5) {
      cutAt(image.offset);
    }
    pageImages.add(image);
    pageHasImage = true;
    used += image.blockHeight;
    hasItem = true;
  }

  void addLine(int index) {
    final lineStart = starts[index];
    final lineEnd = index + 1 < starts.length ? starts[index + 1] : text.length;
    final blank = text.substring(lineStart, lineEnd).trim().isEmpty;
    final lineHeight = metrics[index].height;
    if (hasItem &&
        !blank &&
        (lineStart > pageStart || pageHasImage) &&
        used + lineHeight > height + 0.5) {
      cutAt(lineStart);
    }
    used += lineHeight;
    hasItem = true;
  }

  final imagesByLine = <int, List<PageIllustration>>{};
  for (final entry in placed) {
    imagesByLine.putIfAbsent(entry.line, () => []).add(entry.image);
  }

  for (var i = 0; i < metrics.length; i++) {
    for (final image in imagesByLine[i] ?? const <PageIllustration>[]) {
      addImage(image);
    }
    addLine(i);
  }
  for (final image
      in imagesByLine[metrics.length] ?? const <PageIllustration>[]) {
    addImage(image);
  }

  pages.add(PageSlice(
    start: pageStart,
    end: text.length,
    images: List.unmodifiable(pageImages),
  ));
  return ChapterPagination(pages: pages, headingText: headingText);
}

List<({int line, PageIllustration image})> _placeIllustrations({
  required String text,
  required List<int> starts,
  required int lineCount,
  required double columnWidth,
  required double pageHeight,
  required List<BookIllustration> illustrations,
}) {
  final placed = <({int line, PageIllustration image})>[];
  for (final source in illustrations) {
    if (source.width <= 0 || source.height <= 0 || source.offset < 0) continue;
    final offset = source.offset.clamp(0, text.length);

    // Small images keep their natural size; big ones fit the column.
    var displayWidth = source.width.toDouble() < columnWidth
        ? source.width.toDouble()
        : columnWidth;
    var displayHeight = displayWidth * source.height / source.width;
    var gap = kIllustrationGap;
    final total = displayHeight + gap * 2;
    if (pageHeight > 0 && total > pageHeight) {
      final scale = pageHeight / total;
      displayWidth *= scale;
      displayHeight *= scale;
      gap *= scale;
    }

    var line = lineCount;
    if (starts.isNotEmpty && offset < text.length) {
      line = 0;
      for (var i = 0; i < starts.length; i++) {
        if (starts[i] <= offset) {
          line = i;
        } else {
          break;
        }
      }
    }
    final placement = line < starts.length ? starts[line] : text.length;
    placed.add((
      line: line,
      image: PageIllustration(
        path: source.path,
        offset: placement,
        width: displayWidth,
        height: displayHeight,
        gap: gap,
      ),
    ));
  }
  return placed;
}

/// The typography and viewport used to paginate every chapter of a book.
class PageLayout {
  const PageLayout({
    required this.baseStyle,
    required this.width,
    required this.height,
    required this.textScaler,
  });

  final TextStyle baseStyle;
  final double width;
  final double height;
  final TextScaler textScaler;
}

Future<List<int>> countBookPages({
  required List<Chapter> chapters,
  required PageLayout layout,
  required Future<String> Function(int index) loadChapter,
  Future<List<BookIllustration>> Function(int index)? loadIllustrations,
  int chunkSize = 4,
  void Function(List<int> counts)? onProgress,
  bool Function()? isCurrent,
}) async {
  final counts = <int>[];
  for (var i = 0; i < chapters.length; i++) {
    if (isCurrent != null && !isCurrent()) break;
    final text = await loadChapter(i);
    final illustrations = await loadIllustrations?.call(i) ?? const [];
    final chapter = chapters[i];
    counts.add(
      paginateChapter(
        text: text,
        title: chapter.title,
        level: chapter.level,
        baseStyle: layout.baseStyle,
        width: layout.width,
        height: layout.height,
        textScaler: layout.textScaler,
        illustrations: illustrations,
      ).pageCount,
    );
    if ((i + 1) % chunkSize == 0) {
      onProgress?.call(List.unmodifiable(counts));
      if (i + 1 < chapters.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }
  if (chapters.isNotEmpty && chapters.length % chunkSize != 0) {
    onProgress?.call(List.unmodifiable(counts));
  }
  return counts;
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
