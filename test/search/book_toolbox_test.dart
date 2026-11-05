import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/distill_digest.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/search/book_context.dart';
import 'package:coread/search/book_searcher.dart';
import 'package:coread/search/book_toolbox.dart';

class _NoDigest implements DistillDigestSource {
  @override
  Future<DistillDigest?> load(String bookId) async => null;
}

Chapter chapter(int index, String title) => Chapter(
      id: 'c$index',
      bookId: 'b1',
      index: index,
      title: title,
      startOffset: 0,
      endOffset: 100,
      contentText: '',
      level: 1,
    );

BookToolbox makeToolbox({Map<int, String>? texts}) {
  final chapters = [chapter(0, '第一章 雨夜'), chapter(1, '第二章 风起')];
  final content = texts ??
      {
        0: '雨在夜里落下。' * 40,
        1: '风在吹。' * 40,
      };
  final searcher = BookSearcher(
    loadChapters: (_) async => chapters,
    loadChapterText: (_, index) async => content[index],
    digests: _NoDigest(),
  );
  return BookToolbox(
    book: const BookContext(
      bookId: 'b1',
      title: '测试书',
      author: '',
      brief: '',
    ),
    searcher: searcher,
  );
}

void main() {
  test('search_in_book 返回按章号和偏移标注的命中', () async {
    final raw = await makeToolbox().call(
      'search_in_book',
      '{"query":"雨","limit":2}',
    );
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['hits'], isNotEmpty);
    final first = (json['hits'] as List).first as Map;
    expect(first['chapter'], 1);
    expect(first['offset'], isA<int>());
    expect(first['text'], isA<String>());
  });

  test('参数不是合法 JSON 时返回 error 而不是抛异常', () async {
    final raw = await makeToolbox().call('search_in_book', '查询=雨');
    expect(jsonDecode(raw), {'error': '参数不是合法 JSON'});
  });

  test('缺 query 返回 error', () async {
    final raw = await makeToolbox().call('search_in_book', '{}');
    expect((jsonDecode(raw) as Map)['error'], contains('query'));
  });

  test('limit 被夹到 1..5', () async {
    final raw = await makeToolbox().call(
      'search_in_book',
      '{"query":"雨","limit":99}',
    );
    final hits = (jsonDecode(raw) as Map)['hits'] as List;
    expect(hits.length, lessThanOrEqualTo(5));
  });

  test('章号越界时返回 error（1 基入参 → 0 基查询）', () async {
    final raw = await makeToolbox().call('get_chapter', '{"chapter":99}');
    expect((jsonDecode(raw) as Map)['error'], contains('99'));
  });

  test('get_chapter 截到 max_chars 并回带 1 基章号', () async {
    final raw = await makeToolbox().call(
      'get_chapter',
      '{"chapter":1,"max_chars":50}',
    );
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['chapter'], 1);
    expect((json['text'] as String).length, lessThanOrEqualTo(51));
  });

  test('空正文的书返回可读 error', () async {
    final raw = await makeToolbox(texts: {0: '   ', 1: '风在吹。'}).call(
      'get_chapter',
      '{"chapter":1}',
    );
    expect((jsonDecode(raw) as Map)['error'], contains('正文'));
  });

  test('未知工具名返回 error', () async {
    final raw = await makeToolbox().call('delete_book', '{}');
    expect((jsonDecode(raw) as Map)['error'], contains('delete_book'));
  });

  test('tool spec 里两个工具都有 name 与 parameters', () {
    final names = BookToolbox.specs.map((s) => s.name).toList();
    expect(names, ['search_in_book', 'get_chapter']);
    for (final spec in BookToolbox.specs) {
      expect(spec.description, isNotEmpty);
      expect(spec.parameters['type'], 'object');
    }
  });
}
