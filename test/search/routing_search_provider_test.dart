import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/search/routing_search_provider.dart';
import 'package:coread/search/search_config.dart';
import 'package:coread/search/search_hit.dart';
import 'package:coread/search/search_provider.dart';

class _Recorder implements SearchProvider {
  _Recorder(this.id);
  @override
  final String id;
  int calls = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<List<SearchHit>> search(String query, {int count = 5, CancelToken? cancel}) async {
    calls++;
    return [SearchHit(title: id, snippet: '', source: '', url: null)];
  }
}

void main() {
  test('免费配置走免费源，Tavily 配置走 Tavily', () async {
    final free = _Recorder('free');
    final tavily = _Recorder('tavily');
    var config = const SearchConfig(provider: SearchConfig.free, apiKey: '');
    final router = RoutingSearchProvider(
      config: () => config,
      free: free,
      tavily: tavily,
    );

    expect(router.isConfigured, isTrue);
    await router.search('q');
    expect(free.calls, 1);
    expect(tavily.calls, 0);

    config = const SearchConfig(provider: SearchConfig.tavily, apiKey: 'k');
    await router.search('q');
    expect(tavily.calls, 1);
  });

  test('配置为 off 时抛未配置，而不是返回空结果', () async {
    final router = RoutingSearchProvider(
      config: () => const SearchConfig(),
      free: _Recorder('free'),
      tavily: _Recorder('tavily'),
    );

    expect(router.isConfigured, isFalse);
    await expectLater(
      router.search('q'),
      throwsA(isA<SearchException>().having((e) => e.message, 'message', '未配置联网搜索')),
    );
  });
}
