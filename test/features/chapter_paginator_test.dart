import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/book_illustration.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/features/reader/chapter_paginator.dart';

const _style = TextStyle(fontSize: 16, height: 1.8);

String _longText({int paragraphs = 80}) => List.generate(
      paragraphs,
      (i) => '第$i段：这是一段用于分页测试的中文正文内容。',
    ).join('\n');

ChapterPagination _paginate(String text, {double width = 320, double height = 240}) {
  return paginateChapter(
    text: text,
    title: '第一章',
    level: 1,
    baseStyle: _style,
    width: width,
    height: height,
  );
}

void main() {
  test('splits a long chapter into contiguous non-empty pages', () {
    final text = _longText();
    final pagination = _paginate(text);

    expect(pagination.pageCount, greaterThan(1));
    expect(pagination.pages.first.start, 0);
    expect(pagination.pages.last.end, text.length);
    for (var i = 0; i < pagination.pages.length; i++) {
      final page = pagination.pages[i];
      expect(page.end, greaterThan(page.start));
      if (i > 0) expect(page.start, pagination.pages[i - 1].end);
    }
  });

  test('larger fonts and narrower widths create more pages', () {
    final text = _longText();
    final normal = _paginate(text);
    final big = paginateChapter(
      text: text, title: '第一章', level: 1,
      baseStyle: const TextStyle(fontSize: 24, height: 1.8),
      width: 320, height: 240,
    );
    final narrow = _paginate(text, width: 160);

    expect(big.pageCount, greaterThan(normal.pageCount));
    expect(narrow.pageCount, greaterThan(normal.pageCount));
  });

  test('detects a matching heading and tolerates footnote markers', () {
    expect(matchedHeadingLine('择善[8]\n正文', '择善'), '择善[8]');
    expect(matchedHeadingLine('正文直接开始。\n下一段', '第一章'), isNull);

    final pagination = paginateChapter(
      text: '择善\n正文', title: '择善', level: 2,
      baseStyle: _style, width: 320, height: 240,
    );
    expect(pagination.headingText, '择善');
  });

  test('scales heading styles by level', () {
    expect(headingTextStyle(_style, 1).fontSize, 24);
    expect(headingTextStyle(_style, 1).fontWeight, FontWeight.w700);
    expect(headingTextStyle(_style, 2).fontSize, closeTo(19.2, 0.01));
    expect(headingTextStyle(_style, 2).fontWeight, FontWeight.w600);
  });

  test('treats empty and whitespace-only chapters as one page', () {
    for (final text in ['', '   \n\n  ']) {
      final pagination = _paginate(text);
      expect(pagination.pageCount, 1);
      expect(pagination.pages.single.start, 0);
      expect(pagination.pages.single.end, text.length);
    }
  });

  test('maps offsets to page indexes, clamped at both ends', () {
    final text = _longText();
    final pagination = _paginate(text);

    expect(pagination.pageIndexForOffset(-5), 0);
    expect(pagination.pageIndexForOffset(0), 0);
    expect(pagination.pageIndexForOffset(text.length + 100), pagination.pageCount - 1);
    expect(pagination.pageIndexForOffset(pagination.pages[1].start), 1);
    expect(pagination.pageIndexForOffset(pagination.pages[0].end - 1), 0);
    expect(pagination.pageAt(999).end, pagination.pages.last.end);
  });

  test('counts pages for every chapter and reports progress', () async {
    final chapters = [
      for (var i = 0; i < 3; i++)
        Chapter(
          id: 'c$i',
          bookId: 'b1',
          index: i,
          title: '第${i + 1}章',
          startOffset: i * 1000,
          endOffset: (i + 1) * 1000,
          contentText: '',
        ),
    ];
    final progress = <int>[];
    final counts = await countBookPages(
      chapters: chapters,
      layout: const PageLayout(
        baseStyle: TextStyle(fontSize: 16, height: 1.8),
        width: 320,
        height: 240,
        textScaler: TextScaler.noScaling,
      ),
      loadChapter: (index) async => _longText(paragraphs: 20 + index * 20),
      chunkSize: 1,
      onProgress: (value) => progress.add(value.length),
    );

    expect(counts, hasLength(3));
    expect(counts.every((count) => count >= 1), isTrue);
    expect(progress, [1, 2, 3]);
  });

  test('stops counting once the layout is no longer current', () async {
    final chapters = [
      for (var i = 0; i < 3; i++)
        Chapter(
          id: 'c$i',
          bookId: 'b1',
          index: i,
          title: '第${i + 1}章',
          startOffset: i * 1000,
          endOffset: (i + 1) * 1000,
          contentText: '',
        ),
    ];
    var checks = 0;
    final loads = <int>[];
    final counts = await countBookPages(
      chapters: chapters,
      layout: const PageLayout(
        baseStyle: TextStyle(fontSize: 16, height: 1.8),
        width: 320,
        height: 240,
        textScaler: TextScaler.noScaling,
      ),
      loadChapter: (index) async {
        loads.add(index);
        return _longText(paragraphs: 10);
      },
      chunkSize: 1,
      isCurrent: () => ++checks <= 1,
    );

    expect(loads, [0]);
    expect(counts, hasLength(1));
  });

  test('gives a line taller than the page its own page', () {
    final text = _longText(paragraphs: 10);
    final pagination = _paginate(text, height: 8);

    expect(pagination.pageCount, greaterThan(5));
    expect(pagination.pages.first.start, 0);
    expect(pagination.pages.last.end, text.length);
    for (var i = 1; i < pagination.pages.length; i++) {
      expect(pagination.pages[i].start, pagination.pages[i - 1].end);
    }
  });

  BookIllustration imageFor(int offset, {int width = 320, int height = 160}) =>
      BookIllustration(
        path: '/tmp/pic.png',
        chapterIndex: 0,
        offset: offset,
        width: width,
        height: height,
      );

  ChapterPagination paginateWith(
    String text,
    List<BookIllustration> images, {
    double width = 320,
    double height = 240,
  }) =>
      paginateChapter(
        text: text,
        title: '第一章',
        level: 1,
        baseStyle: _style,
        width: width,
        height: height,
        illustrations: images,
      );

  test('places an illustration at the line start that contains it', () {
    final text = _longText(paragraphs: 20);
    final paragraph = text.indexOf('第5段');
    final pagination = paginateWith(text, [imageFor(paragraph + 3)]);

    final pagesWithImages =
        pagination.pages.where((page) => page.images.isNotEmpty).toList();
    expect(pagesWithImages, hasLength(1));
    expect(pagesWithImages.single.images.single.offset, paragraph);
    expect(pagesWithImages.single.images.single.width, 320);
    expect(pagesWithImages.single.images.single.height, 160);
  });

  test('moves a whole illustration to the next page when it does not fit',
      () {
    final text = _longText(paragraphs: 20);
    final plain = _paginate(text);
    final offset = List.generate(20, (i) => text.indexOf('第$i段'))
        .lastWhere((o) => plain.pageIndexForOffset(o) == 0);

    final withImage = paginateWith(text, [imageFor(offset, height: 200)]);
    final page = withImage.pages.firstWhere((p) => p.images.isNotEmpty);

    expect(page.start, offset);
    expect(withImage.pageCount, greaterThan(plain.pageCount));
  });

  test('scales a tall illustration into the page', () {
    final pagination = paginateWith(
      _longText(paragraphs: 3),
      [imageFor(0, width: 100, height: 1000)],
    );
    final image = pagination.pages.first.images.single;
    expect(image.height + image.gap * 2, lessThanOrEqualTo(240 + 0.5));
    expect(image.width, lessThan(320));
  });

  test('allows an image-only page and maps its offset to it', () {
    final text = _longText(paragraphs: 20);
    final plain = _paginate(text);
    final offset = List.generate(20, (i) => text.indexOf('第$i段'))
        .lastWhere((o) => plain.pageIndexForOffset(o) == 0);
    final pagination = paginateWith(
      text,
      [imageFor(offset, width: 320, height: 2000)],
    );

    final imageOnly = pagination.pages.where(
      (page) => page.start == page.end && page.images.isNotEmpty,
    );
    expect(imageOnly, isNotEmpty);
    expect(pagination.pages[pagination.pageIndexForOffset(offset)].images,
        isNotEmpty);
  });

  test('splits a page into text fragments around illustrations', () {
    final page = PageSlice(
      start: 10,
      end: 40,
      images: [
        for (final offset in [20, 20, 40])
          PageIllustration(
            path: 'x',
            offset: offset,
            width: 100,
            height: 50,
            gap: 8,
          ),
      ],
    );
    expect(
      pageTextFragments(page).map((f) => (f.start, f.end)),
      [(10, 20), (20, 40)],
    );
    expect(pageTextFragments(const PageSlice(start: 7, end: 7)), isEmpty);
  });

  test('countBookPages loads illustrations per chapter', () async {
    final image = imageFor(0);
    final counts = await countBookPages(
      chapters: [
        Chapter(
          id: 'c0',
          bookId: 'b',
          index: 0,
          title: '第一章',
          startOffset: 0,
          endOffset: 100,
          contentText: '',
        ),
      ],
      layout: const PageLayout(
        baseStyle: TextStyle(fontSize: 16, height: 1.8),
        width: 320,
        height: 240,
        textScaler: TextScaler.noScaling,
      ),
      loadChapter: (index) async => _longText(paragraphs: 20),
      loadIllustrations: (index) async => index == 0 ? [image] : const [],
    );
    expect(
      counts.single,
      paginateWith(_longText(paragraphs: 20), [image]).pageCount,
    );
  });
}
