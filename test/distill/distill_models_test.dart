import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/distill_models.dart';
import 'package:coread/distill/distill_prompts.dart';

void main() {
  test('parses fenced json into a map result', () {
    const raw = '''
好的，结果如下：
```json
{"points": ["福贵输光家产", "父亲气死"], "entities": ["福贵", "家珍"],
 "toneCues": ["自嘲"], "quotes": ["我年轻的时候真是个败家子"]}
```
''';

    final result = parseMapResult(raw);

    expect(result.points, ['福贵输光家产', '父亲气死']);
    expect(result.entities, ['福贵', '家珍']);
    expect(result.quotes, ['我年轻的时候真是个败家子']);
  });

  test('missing keys fall back to empty lists', () {
    final result = parseMapResult('{"points": ["只有要点"]}');

    expect(result.points, ['只有要点']);
    expect(result.entities, isEmpty);
    expect(result.toneCues, isEmpty);
    expect(result.quotes, isEmpty);
  });

  test('malformed json throws DistillParseException', () {
    expect(
      () => parseMapResult('{"points": ["未闭合"'),
      throwsA(isA<DistillParseException>()),
    );
    expect(
      () => parseOverview('完全不是 JSON'),
      throwsA(isA<DistillParseException>()),
    );
  });

  test('parses part results with per-chapter gists', () {
    const raw = '{"summary": "这一组讲福贵败家", '
        '"chapters": [{"chapterIndex": 0, "title": "第一章", "gist": "输光家产"}, '
        '{"chapterIndex": "1", "title": "第二章", "gist": "被抓壮丁"}]}';

    final result = parsePartResult(raw);

    expect(result.summary, '这一组讲福贵败家');
    expect(result.chapters.map((c) => c.chapterIndex), [0, 1]);
    expect(result.chapters.last.gist, '被抓壮丁');
  });

  test('parses the book overview including structure arcs', () {
    const raw = '{"oneLiner": "一个人一生的苦难", "synopsis": "福贵……", '
        '"themes": ["活着", "苦难"], '
        '"structure": [{"title": "败家", "chapters": [0, 1], "note": "铺垫"}], '
        '"argument": "活着本身即意义"}';

    final overview = parseOverview(raw);

    expect(overview.oneLiner, '一个人一生的苦难');
    expect(overview.themes, ['活着', '苦难']);
    expect(overview.structure.single.chapters, [0, 1]);
    expect(overview.argument, '活着本身即意义');
  });

  test('parses the tone profile', () {
    const raw = '{"overall": "克制的悲悯", "narrator": "老年福贵自述", '
        '"arc": [{"chapterIndex": 0, "tone": "荒诞"}, {"chapterIndex": 3, "tone": "平静"}], '
        '"style": ["白描"], "sampleQuotes": ["少年去游荡"]}';

    final tone = parseTone(raw);

    expect(tone.overall, '克制的悲悯');
    expect(tone.arc.map((a) => a.chapterIndex), [0, 3]);
    expect(tone.style, ['白描']);
  });

  test('parses cards from a bare array', () {
    const raw = '[{"slug": "loss-of-fortune", "title": "败家", "type": "case", '
        '"definition": "福贵把家产输光", "sourceChapters": [0], "quote": "我输光了"}]';

    final cards = parseCards(raw);

    expect(cards, hasLength(1));
    expect(cards.single.slug, 'loss-of-fortune');
    expect(cards.single.sourceChapters, [0]);
  });

  test('keeps cards whose source chapters are unknown at parse time', () {
    const raw = '{"cards": [{"slug": "a", "title": "A", "definition": "d", '
        '"sourceChapters": [99]}]}';

    final cards = parseCards(raw);

    expect(cards.single.sourceChapters, [99]);
    expect(cards.single.type, 'case');
  });

  test('prompts carry the book title and forbid invention', () {
    final prompts = overviewPrompt(
      ['第一组梗概'],
      bookTitle: '活着',
      author: '余华',
    );

    expect(prompts.first.content, contains('不编造'));
    expect(prompts.last.content, contains('活着'));
    expect(prompts.last.content, contains('余华'));
    expect(prompts.last.content, contains('第一组梗概'));
  });
}
