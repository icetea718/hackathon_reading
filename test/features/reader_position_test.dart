import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
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

  test('offsetForPosition never exceeds chapter end', () {
    final chapter = _chapter(0, 10, '0123456789');
    expect(offsetForPosition(chapter, 1.0), chapter.startOffset + 10);
    expect(offsetForPosition(chapter, 2.0), chapter.endOffset);
    expect(offsetForPosition(chapter, -1.0), chapter.startOffset);
  });
}
