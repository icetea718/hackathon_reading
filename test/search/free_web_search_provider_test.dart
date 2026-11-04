import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/search/free_web_search_provider.dart';
import 'package:hackathon_reading/search/search_provider.dart';

const _rss = '''<?xml version="1.0" encoding="utf-8" ?>
<rss version="2.0"><channel><title>必应：AI news</title>
<item>
  <title>AI News | Latest</title>
  <link>https://www.artificialintelligence-news.com/</link>
  <description>AI News delivers the &lt;b&gt;latest&lt;/b&gt; updates.</description>
  <pubDate>周三, 04 11月 2026 08:39:00 GMT</pubDate>
</item>
<item>
  <title>每日 AI 资讯 - 猫目</title>
  <link>https://maomu.com/news</link>
  <description>从具身智能机器人到 AI 智能体手机。</description>
  <pubDate>周三, 04 11月 2026 10:05:00 GMT</pubDate>
</item>
<item>
  <title>TechCrunch</title>
  <link>https://techcrunch.com/category/artificial-intelligence/</link>
  <description>Read the latest.</description>
  <pubDate>not a date</pubDate>
</item>
</channel></rss>''';

void main() {
  final requests = <FreeWebRequest>[];

  FreeWebSearchProvider providerReturning(
    FreeWebResponse response, {
    Object? throws,
  }) {
    return FreeWebSearchProvider(
      transport: (request, cancel) async {
        requests.add(request);
        if (throws != null) throw throws;
        return response;
      },
    );
  }

  setUp(requests.clear);

  test('把 RSS 条目映射成 hits，source 取域名', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 200, body: _rss),
    );

    final hits = await provider.search('AI news');

    expect(hits, hasLength(3));
    expect(hits.first.title, 'AI News | Latest');
    expect(hits.first.url, 'https://www.artificialintelligence-news.com/');
    expect(hits.first.source, 'artificialintelligence-news.com');
    expect(hits.first.snippet, 'AI News delivers the latest updates.');
    expect(hits.first.publishedAt, '2026-11-04T08:39:00.000Z');
    expect(hits.last.publishedAt, isNull);

    final uri = requests.single.uri;
    expect(uri.host, 'cn.bing.com');
    expect(uri.queryParameters['q'], 'AI news');
    expect(uri.queryParameters['format'], 'rss');
  });

  test('count 夹到 1..10', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 200, body: _rss),
    );

    expect(await provider.search('x', count: 2), hasLength(2));
    expect(await provider.search('x', count: 0), hasLength(1));
    expect(await provider.search('x', count: 99), hasLength(3));
  });

  test('非 RSS 响应抛 SearchException', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 200, body: '<html>blocked</html>'),
    );

    await expectLater(
      provider.search('x'),
      throwsA(isA<SearchException>()),
    );
  });

  test('HTTP 500 带状态码', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 500, body: 'oops'),
    );

    await expectLater(
      provider.search('x'),
      throwsA(
        isA<SearchException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', contains('HTTP 500')),
      ),
    );
  });

  test('网络错误与取消使用既有文案', () async {
    final offline = providerReturning(
      const FreeWebResponse(statusCode: 200, body: ''),
      throws: SearchException('网络错误：连接失败'),
    );
    await expectLater(offline.search('x'), throwsA(isA<SearchException>()));

    final canceled = providerReturning(
      const FreeWebResponse(statusCode: 200, body: _rss),
      throws: SearchException('已取消'),
    );
    await expectLater(
      canceled.search('x'),
      throwsA(
        isA<SearchException>()
            .having((e) => e.message, 'message', '已取消'),
      ),
    );
  });

  test('没有 item 时返回空列表', () async {
    final provider = providerReturning(
      const FreeWebResponse(
        statusCode: 200,
        body: '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>',
      ),
    );

    expect(await provider.search('x'), isEmpty);
  });

  test('免 Key 即已配置', () {
    final provider = FreeWebSearchProvider();
    expect(provider.id, 'free');
    expect(provider.isConfigured, isTrue);
  });
}
