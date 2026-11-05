import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/distill_digest.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/search/book_searcher.dart';

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

void main() {
  test('命中按分数降序，每段不超过窗口长度，offset 是窗口起点', () async {
    final texts = {
      0: '雨' * 400,
      1: '风' * 400,
    };
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章'), chapter(1, '第二章')],
      loadChapterText: (_, index) async => texts[index],
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨', limit: 2);

    expect(result.hits, isNotEmpty);
    expect(result.hits.first.chapterIndex, 0);
    expect(result.hits.first.offset % 100, 0);
    expect(result.hits.first.text.length, lessThanOrEqualTo(200));
    final scores = result.hits.map((h) => h.score).toList();
    expect(scores, orderedEquals([...scores]..sort((a, b) => b.compareTo(a))));
  });

  test('chapter 参数只扫那一章（0 基入参）', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章'), chapter(1, '第二章')],
      loadChapterText: (_, index) async => index == 0 ? '雨雨雨' : '雨雨雨',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨', chapter: 1, limit: 3);

    expect(result.hits.every((h) => h.chapterIndex == 1), isTrue);
  });

  test('没有命中时返回空列表而不是抛错', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章')],
      loadChapterText: (_, _) async => '风在吹',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨');

    expect(result.hits, isEmpty);
    expect(result.truncated, isFalse);
  });

  test('未蒸馏时退化为按章序取前 maxChapters 章（不返回空）', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async =>
          [for (var i = 0; i < 12; i++) chapter(i, '第${i + 1}章')],
      loadChapterText: (_, _) async => '雨在夜里落下',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨');

    expect(result.hits, isNotEmpty);
  });

  test('超过 maxScanChars 时置 truncated', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章'), chapter(1, '第二章')],
      loadChapterText: (_, _) async => '雨' * 5000,
      digests: _NoDigest(),
      maxScanChars: 1000,
    );

    final result = await searcher.search('b1', '雨');

    expect(result.truncated, isTrue);
  });

  test('同一章正文在一次检索里只读一次', () async {
    var loads = 0;
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章')],
      loadChapterText: (_, _) async {
        loads++;
        return '雨' * 2000;
      },
      digests: _NoDigest(),
    );

    await searcher.search('b1', '雨');
    await searcher.search('b1', '雨');

    expect(loads, 1);
  });

  test('整句命中的窗口排在同一批散词命中之前', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章')],
      loadChapterText: (_, _) async =>
          '${'雨' * 200}${'风' * 200}雨夜里的雨声',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨夜里的雨声', limit: 3);

    expect(result.hits, isNotEmpty);
    expect(result.hits.first.text, contains('雨夜里的雨声'));
  });

  test('单字查询会扫到前 maxChapters 章之外', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async =>
          [for (var i = 0; i < 20; i++) chapter(i, '第${i + 1}章')],
      loadChapterText: (_, index) async =>
          index == 19 ? '雨落在最后一章' : '风在吹',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨');

    expect(result.hits, isNotEmpty);
    expect(result.hits.first.chapterIndex, 19);
  });

  test('空 query 直接返回空结果', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章')],
      loadChapterText: (_, _) async => '雨在夜里落下',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '   ');

    expect(result.hits, isEmpty);
    expect(result.truncated, isFalse);
  });
}
