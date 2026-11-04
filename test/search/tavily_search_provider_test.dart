import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/settings_repository.dart';
import 'package:coread/search/search_config.dart';
import 'package:coread/search/search_provider.dart';
import 'package:coread/search/tavily_search_provider.dart';

void main() {
  final requests = <TavilyRequest>[];

  TavilySearchProvider providerReturning(
    TavilyResponse response, {
    SearchConfig config = const SearchConfig(provider: 'tavily', apiKey: 'key'),
  }) {
    return TavilySearchProvider(
      config: () => config,
      transport: (request, cancel) async {
        requests.add(request);
        return response;
      },
    );
  }

  setUp(requests.clear);

  test('parses results into hits and derives the source host', () async {
    final provider = providerReturning(
      TavilyResponse(
        statusCode: 200,
        body: jsonEncode({
          'results': [
            {
              'title': 'Flutter 3.47 发布',
              'url': 'https://www.flutter.dev/release/3-47',
              'content': '本次发布包含 Impeller 改进。',
            },
            {
              'title': 'Dart 3.13',
              'url': 'https://dart.dev/blog/3-13',
              'content': '新的格式化器。',
            },
          ],
        }),
      ),
    );

    final hits = await provider.search('flutter 最新版本');

    expect(hits, hasLength(2));
    expect(hits.first.title, 'Flutter 3.47 发布');
    expect(hits.first.snippet, '本次发布包含 Impeller 改进。');
    expect(hits.first.source, 'flutter.dev');
    expect(hits.first.url, 'https://www.flutter.dev/release/3-47');
    expect(hits.last.source, 'dart.dev');

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['api_key'], 'key');
    expect(body['query'], 'flutter 最新版本');
    expect(body['max_results'], 5);
  });

  test('surfaces the HTTP status when the endpoint rejects the key', () async {
    final provider = providerReturning(
      const TavilyResponse(statusCode: 401, body: '{"detail":"bad key"}'),
    );

    await expectLater(
      provider.search('ping'),
      throwsA(
        isA<SearchException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', contains('HTTP 401')),
      ),
    );
  });

  test('an empty key is not configured and never hits the network', () async {
    final provider = providerReturning(
      const TavilyResponse(statusCode: 200, body: '{"results":[]}'),
      config: const SearchConfig(),
    );

    expect(provider.isConfigured, isFalse);
    await expectLater(
      provider.search('ping'),
      throwsA(
        isA<SearchException>().having(
          (error) => error.message,
          'message',
          '未配置联网搜索',
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('tolerates results without a url', () async {
    final provider = providerReturning(
      TavilyResponse(
        statusCode: 200,
        body: jsonEncode({
          'results': [
            {'title': '无链接', 'content': '片段'},
          ],
        }),
      ),
    );

    final hits = await provider.search('ping', count: 1);

    expect(hits.single.url, isNull);
    expect(hits.single.source, '');
    expect(requests.single.body, contains('"max_results":1'));
  });

  test('config round-trips through the settings table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SearchConfigStore(SettingsRepository(db));

    expect(await store.load(), const SearchConfig());

    await store.save(const SearchConfig(provider: 'tavily', apiKey: 'secret'));
    final restored = await store.load();

    expect(restored.provider, 'tavily');
    expect(restored.apiKey, 'secret');
    expect(restored.isEnabled, isTrue);
    expect(const SearchConfig(provider: 'tavily').isEnabled, isFalse,
        reason: 'a provider without a key cannot search');
  });
}
