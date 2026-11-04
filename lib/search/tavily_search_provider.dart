import 'dart:convert';
import 'dart:io';

import '../distill/llm/llm_client.dart';
import 'search_config.dart';
import 'search_hit.dart';
import 'search_provider.dart';

class TavilyRequest {
  const TavilyRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class TavilyResponse {
  const TavilyResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// Injected in tests; the default implementation talks to the real endpoint.
typedef TavilyTransport = Future<TavilyResponse> Function(
  TavilyRequest request,
  CancelToken? cancel,
);

/// Tavily's `/search` endpoint, adapted to [SearchProvider].
class TavilySearchProvider implements SearchProvider {
  TavilySearchProvider({required this.config, TavilyTransport? transport})
      : _transport = transport ?? _httpTransport;

  static const endpoint = 'https://api.tavily.com/search';
  static const defaultUrlTimeout = Duration(seconds: 20);

  /// Read on every call, so a settings change applies to the next question.
  final SearchConfig Function() config;
  final TavilyTransport _transport;

  @override
  String get id => SearchConfig.tavily;

  @override
  bool get isConfigured => config().isConfigured;

  @override
  Future<List<SearchHit>> search(
    String query, {
    int count = 5,
    CancelToken? cancel,
  }) async {
    final settings = config();
    if (!settings.isConfigured) {
      throw SearchException('未配置联网搜索');
    }

    final request = TavilyRequest(
      uri: Uri.parse(endpoint),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'api_key': settings.apiKey.trim(),
        'query': query,
        'max_results': count,
        'search_depth': 'basic',
      }),
    );

    final response = await _transport(request, cancel).timeout(
      defaultUrlTimeout,
      onTimeout: () => throw SearchException('联网搜索超时'),
    );

    if (response.statusCode != 200) {
      throw SearchException(
        'HTTP ${response.statusCode}: ${_snippet(response.body)}',
        statusCode: response.statusCode,
      );
    }

    return _parse(response.body);
  }

  List<SearchHit> _parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw SearchException('搜索结果不是 JSON：${_snippet(body)}');
    }
    final results = decoded is Map<String, dynamic> ? decoded['results'] : null;
    if (results is! List) return const [];

    return [
      for (final entry in results)
        if (entry is Map<String, dynamic>) _toHit(entry),
    ];
  }

  SearchHit _toHit(Map<String, dynamic> result) {
    final url = (result['url'] as String?)?.trim();
    return SearchHit(
      title: (result['title'] as String? ?? '').trim(),
      snippet: (result['content'] as String? ?? '').trim(),
      source: _hostOf(url),
      url: url == null || url.isEmpty ? null : url,
      publishedAt: result['published_date'] as String?,
    );
  }

  static String _hostOf(String? url) {
    if (url == null || url.isEmpty) return '';
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _snippet(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 120 ? flat : '${flat.substring(0, 120)}…';
  }

  static Future<TavilyResponse> _httpTransport(
    TavilyRequest request,
    CancelToken? cancel,
  ) async {
    final client = HttpClient();
    void abort() {
      if (cancel?.isCanceled ?? false) client.close(force: true);
    }

    cancel?.addListener(abort);
    try {
      final httpRequest = await client.postUrl(request.uri);
      request.headers.forEach(httpRequest.headers.set);
      final bytes = utf8.encode(request.body);
      httpRequest.headers.contentLength = bytes.length;
      httpRequest.add(bytes);
      final response = await httpRequest.close();
      final body = await response.transform(utf8.decoder).join();
      if (cancel?.isCanceled ?? false) throw SearchException('已取消');
      return TavilyResponse(statusCode: response.statusCode, body: body);
    } on SocketException catch (error) {
      throw SearchException('网络错误：${error.message}');
    } finally {
      cancel?.removeListener(abort);
      client.close();
    }
  }
}
