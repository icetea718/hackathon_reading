import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:coread/search/search_step.dart';

void main() {
  test('toJson 带上工具名、摘要、章号、命中数与耗时', () {
    const step = SearchStep(
      tool: 'search_in_book',
      summary: '检索「雨」',
      chapters: [3, 7],
      hits: 2,
      ms: 41,
    );

    expect(step.toJson(), {
      'tool': 'search_in_book',
      'summary': '检索「雨」',
      'chapters': [3, 7],
      'hits': 2,
      'ms': 41,
    });
  });

  test('列表往返保持一致', () {
    const steps = [
      SearchStep(
        tool: 'search_in_book',
        summary: '检索「雨」',
        chapters: [3],
        hits: 1,
        ms: 12,
      ),
      SearchStep(tool: 'get_chapter', summary: '读第 7 章', chapters: [7], hits: 0, ms: 5),
    ];

    final restored = SearchStep.listFromJson(SearchStep.listToJson(steps));

    expect(restored.map((s) => s.toJson()).toList(),
        steps.map((s) => s.toJson()).toList());
  });

  test('坏 JSON 与空值返回空列表', () {
    expect(SearchStep.listFromJson(null), isEmpty);
    expect(SearchStep.listFromJson('  '), isEmpty);
    expect(SearchStep.listFromJson('{不是数组'), isEmpty);
  });

  test('非 Map 的元素被跳过', () {
    final json = jsonEncode([
      {'tool': 'get_chapter', 'summary': '读第 1 章', 'chapters': [1], 'hits': 0, 'ms': 3},
      'junk',
    ]);

    expect(SearchStep.listFromJson(json).length, 1);
  });

  test('缺字段时给安全默认值', () {
    final restored = SearchStep.listFromJson('[{"tool":"get_chapter"}]');

    expect(restored.single.summary, '');
    expect(restored.single.chapters, isEmpty);
    expect(restored.single.hits, 0);
    expect(restored.single.ms, 0);
  });
}
