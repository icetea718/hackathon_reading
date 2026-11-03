import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/distill/distill_planner.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';

void main() {
  Chapter chapter(int index, String text, {String? title}) {
    return Chapter(
      id: 'c$index',
      bookId: 'book',
      index: index,
      title: title ?? '第$index章',
      startOffset: 0,
      endOffset: text.length,
      contentText: text,
    );
  }

  String paragraphs(int count, {int wordsPerParagraph = 50}) {
    return List.generate(count, (i) => '${'字' * wordsPerParagraph}$i\n').join();
  }

  test('splits a long chapter into segments within the limit', () {
    final text = paragraphs(300); // ~15k chars
    final plan = DistillPlanner().plan([chapter(0, text)]);

    expect(plan.segments.length, greaterThan(1));
    for (final segment in plan.segments) {
      expect(segment.text.length, lessThanOrEqualTo(6000));
      expect(segment.chapterIndex, 0);
    }
    // Every segment except the last ends on a paragraph break.
    for (final segment in plan.segments.take(plan.segments.length - 1)) {
      expect(segment.text.endsWith('\n'), isTrue);
      expect(text[segment.charEndInChapter - 1], '\n');
    }
    expect(plan.segments.first.charStartInChapter, 0);
    expect(plan.segments.last.charEndInChapter, text.length);
  });

  test('keeps segments inside their own chapter', () {
    final plan = DistillPlanner().plan([
      chapter(0, paragraphs(200)),
      chapter(1, '第二章很短。'),
    ]);

    final second = plan.segments.where((s) => s.chapterIndex == 1).toList();
    expect(second, hasLength(1));
    expect(second.single.text, '第二章很短。');
  });

  test('a single-chapter book still yields several segments', () {
    final plan = DistillPlanner().plan([chapter(0, paragraphs(250))]);

    expect(plan.segments.length, greaterThanOrEqualTo(2));
    expect(plan.parts, hasLength(1));
    expect(plan.parts.single.chapterIndexes, [0]);
  });

  test('parts respect the character budget', () {
    final plan = DistillPlanner().plan([
      for (var i = 0; i < 6; i++) chapter(i, paragraphs(100)),
    ]);

    for (final part in plan.parts) {
      final chars = part.segments.fold<int>(0, (sum, s) => sum + s.text.length);
      expect(chars, lessThanOrEqualTo(60000));
      expect(part.segments, isNotEmpty);
    }
    expect(
      plan.parts.expand((p) => p.chapterIndexes).toSet(),
      {0, 1, 2, 3, 4, 5},
    );
  });

  test('never leaves a part with a single chapter when it could merge', () {
    final plan = DistillPlanner().plan([
      chapter(0, paragraphs(20)),
      chapter(1, paragraphs(20)),
      chapter(2, paragraphs(20)),
    ]);

    for (final part in plan.parts) {
      expect(part.chapterIndexes.length, greaterThanOrEqualTo(2));
    }
  });

  test('skips empty chapters and keeps keys contiguous', () {
    final plan = DistillPlanner().plan([
      chapter(0, paragraphs(10)),
      chapter(1, '   '),
      chapter(2, paragraphs(10)),
    ]);

    expect(plan.segments.map((s) => s.key), ['seg-0000', 'seg-0001']);
    expect(plan.segments.map((s) => s.chapterIndex), [0, 2]);
    expect(plan.parts.map((p) => p.key), ['part-00']);
  });
}
