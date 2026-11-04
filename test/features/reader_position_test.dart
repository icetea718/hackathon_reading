import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/features/reader/chapter_paginator.dart';
import 'package:hackathon_reading/features/reader/reader_position.dart';

Chapter _chapter(int index, int start, String text) {
  return Chapter(
    id: 'c$index',
    bookId: 'b1',
    index: index,
    title: '第${index + 1}章',
    startOffset: start,
    endOffset: start + text.length,
    contentText: text,
  );
}

void main() {
  final chapters = [
    _chapter(0, 0, 'abcdef'),
    _chapter(1, 6, 'ghij'),
    _chapter(2, 10, 'klm'),
  ];

  test('locates an offset in the correct chapter', () {
    final location = locateAnchor(chapters, 8);
    expect(location.chapterIndex, 1);
    expect(location.fraction, closeTo(0.5, 1e-9));
  });

  test('clamps offsets before the start and past the end', () {
    final before = locateAnchor(chapters, -5);
    expect(before.chapterIndex, 0);
    expect(before.fraction, 0.0);

    final after = locateAnchor(chapters, 100);
    expect(after.chapterIndex, 2);
    expect(after.fraction, 1.0);
  });

  test('handles empty chapter list', () {
    final location = locateAnchor(const [], 10);
    expect(location.chapterIndex, 0);
    expect(location.fraction, 0.0);
  });

  test('maps a boundary offset to the start of the next chapter', () {
    final location = locateAnchor(chapters, 6);
    expect(location.chapterIndex, 1);
    expect(location.fraction, 0.0);
  });

  test('shifts a page-local selection into the book', () {
    final chapter = _chapter(1, 6, 'ghij');
    expect(
      absoluteOffsetForPageSelection(
        chapter,
        const PageSlice(start: 2, end: 4),
        1,
      ),
      9,
    );
  });

  test('uses offsets when chapter content is not loaded', () {
    final summaries = [
      for (var i = 0; i < chapters.length; i++)
        Chapter(
          id: 's$i',
          bookId: 'b1',
          index: i,
          title: '第${i + 1}章',
          startOffset: chapters[i].startOffset,
          endOffset: chapters[i].endOffset,
          contentText: '',
        ),
    ];
    final location = locateAnchor(summaries, 8);
    expect(location.chapterIndex, 1);
    expect(location.fraction, closeTo(0.5, 1e-9));
  });

  test('anchor offsets stay inside the chapter at both ends', () {
    final chapter = _chapter(0, 10, '0123456789');
    expect(anchorOffsetForFraction(chapter, 0.0), chapter.startOffset + 1);
    expect(anchorOffsetForFraction(chapter, 1.0), chapter.endOffset - 1);

    final top = locateAnchor([chapter], anchorOffsetForFraction(chapter, 0.0));
    expect(top.chapterIndex, 0);
    final bottom = locateAnchor(
      [chapter],
      anchorOffsetForFraction(chapter, 1.0),
    );
    expect(bottom.chapterIndex, 0);
  });

  test('offsetForPosition never exceeds chapter end', () {
    final chapter = _chapter(0, 10, '0123456789');
    expect(offsetForPosition(chapter, 1.0), chapter.startOffset + 10);
    expect(offsetForPosition(chapter, 2.0), chapter.endOffset);
    expect(offsetForPosition(chapter, -1.0), chapter.startOffset);
  });
}
