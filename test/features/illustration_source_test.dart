import 'package:flutter_test/flutter_test.dart';
import 'package:coread/features/reader/chapter_paginator.dart';
import 'package:coread/features/reader/illustration_source.dart';

void main() {
  const text = '第一页内容第二页内容第三页内容';
  const pagination = ChapterPagination(
    pages: [
      PageSlice(start: 0, end: 5),
      PageSlice(start: 5, end: 10),
      PageSlice(start: 10, end: 15),
    ],
    headingText: null,
  );

  test('the current page only carries its own slice', () {
    expect(
      illustrationTextForSource(
        source: IllustrationSource.page,
        chapterText: text,
        pagination: pagination,
        startPage: 1,
        endPage: 1,
      ),
      '第二页内容',
    );
  });

  test('a spread carries both of its pages', () {
    expect(
      illustrationTextForSource(
        source: IllustrationSource.page,
        chapterText: text,
        pagination: pagination,
        startPage: 0,
        endPage: 1,
      ),
      '第一页内容第二页内容',
    );
  });

  test('nearby pages reach one page before and after', () {
    expect(
      illustrationTextForSource(
        source: IllustrationSource.nearby,
        chapterText: text,
        pagination: pagination,
        startPage: 1,
        endPage: 1,
      ),
      text,
    );
    expect(
      illustrationTextForSource(
        source: IllustrationSource.nearby,
        chapterText: text,
        pagination: pagination,
        startPage: 0,
        endPage: 0,
      ),
      '第一页内容第二页内容',
    );
  });

  test('the chapter source always takes the whole text', () {
    expect(
      illustrationTextForSource(
        source: IllustrationSource.chapter,
        chapterText: '  $text  ',
        pagination: pagination,
        startPage: 1,
        endPage: 1,
      ),
      text,
    );
  });

  test('without pagination any source falls back to the chapter', () {
    for (final source in IllustrationSource.values) {
      expect(
        illustrationTextForSource(
          source: source,
          chapterText: text,
          pagination: null,
          startPage: 1,
          endPage: 1,
        ),
        text,
      );
    }
  });

  test('out-of-range pages are clamped to the chapter', () {
    expect(
      illustrationTextForSource(
        source: IllustrationSource.page,
        chapterText: text,
        pagination: pagination,
        startPage: 99,
        endPage: 99,
      ),
      '第三页内容',
    );
  });
}
