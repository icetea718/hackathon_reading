import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../distill/llm/llm_client.dart';
import 'search_config.dart';
import 'search_hit.dart';
import 'search_provider.dart';
import 'url_host.dart';

class FreeWebRequest {
  const FreeWebRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class FreeWebResponse {
  const FreeWebResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// Injected in tests; the default implementation talks to the real endpoint.
typedef FreeWebTransport = Future<FreeWebResponse> Function(
  FreeWebRequest request,
  CancelToken? cancel,
);

/// The key-free web source: Bing's RSS search feed, adapted to [SearchProvider].
///
/// Bing answers `?format=rss` with a plain RSS 2.0 document, so the whole
/// provider is one GET plus an XML walk. Nothing here needs an api key, which
/// is why [isConfigured] is unconditionally true.
class FreeWebSearchProvider implements SearchProvider {
  FreeWebSearchProvider({FreeWebTransport? transport})
      : _transport = transport ?? _httpTransport;

  static const endpoint = 'https://cn.bing.com/search';
  static const defaultUrlTimeout = Duration(seconds: 20);

  static final _endpointUri = Uri.parse(endpoint);

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// Bing's RSS `pubDate` for the Chinese site looks like
  /// `周三, 04 11月 2026 08:39:00 GMT` — day first, then the month number.
  static final _localizedDate = RegExp(
    r'^[^,]+, (\d{1,2}) (\d{1,2})月 (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  );

  final FreeWebTransport _transport;

  @override
  String get id => SearchConfig.free;

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchHit>> search(
    String query, {
    int count = 5,
    CancelToken? cancel,
  }) async {
    final limit = count.clamp(1, 10).toInt();
    final request = FreeWebRequest(
      uri: Uri.https(
        _endpointUri.host,
        _endpointUri.path,
        {'q': query, 'format': 'rss'},
      ),
      headers: const {
        'user-agent': _userAgent,
        'accept-language': 'zh-CN,zh;q=0.9',
      },
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

    final hits = _parse(response.body);
    return hits.length <= limit ? hits : hits.sublist(0, limit);
  }

  /// A document that is not RSS at all is an error page, not an empty result:
  /// Bing answers a blocked request with HTML. A well-formed RSS document
  /// without items is a legitimately empty result.
  List<SearchHit> _parse(String body) {
    final XmlDocument document;
    try {
      // Bing HTML-escapes its snippets, so `&lt;b&gt;` arrives intact, but its
      // feed can also carry HTML-only entities such as `&nbsp;`; the html5
      // mapping resolves those instead of failing the whole parse.
      document = XmlDocument.parse(
        body,
        entityMapping: const XmlDefaultEntityMapping.html5(),
      );
    } on XmlParserException {
      throw SearchException('搜索结果不是 RSS：${_snippet(body)}');
    }
    final isRss = document.descendants
        .whereType<XmlElement>()
        .any((element) => element.name.local == 'rss');
    if (!isRss) {
      throw SearchException('搜索结果不是 RSS：${_snippet(body)}');
    }
    return [
      for (final item in document.findAllElements('item')) _toHit(item),
    ];
  }

  static SearchHit _toHit(XmlElement item) {
    final url = _textOf(item, 'link').trim();
    return SearchHit(
      title: _textOf(item, 'title').trim(),
      snippet: _plainText(_textOf(item, 'description')),
      source: hostOf(url),
      url: url.isEmpty ? null : url,
      publishedAt: _publishedAt(_textOf(item, 'pubDate')),
    );
  }

  static String _textOf(XmlElement parent, String name) {
    for (final child in parent.findElements(name)) {
      return child.innerText;
    }
    return '';
  }

  /// Bing bolds the matched words with `<b>` tags; entities are already
  /// decoded by the XML parser, so only the markup and the whitespace go.
  static String _plainText(String raw) => raw
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String? _publishedAt(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final httpDate = _tryHttpDate(text);
    if (httpDate != null) return httpDate.toIso8601String();
    final match = _localizedDate.firstMatch(text);
    if (match == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    ).toIso8601String();
  }

  /// RFC 1123, as Dart itself reads it; null when the string is something else.
  static DateTime? _tryHttpDate(String text) {
    try {
      return HttpDate.parse(text);
    } catch (_) {
      return null;
    }
  }

  static String _snippet(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 120 ? flat : '${flat.substring(0, 120)}…';
  }

  static Future<FreeWebResponse> _httpTransport(
    FreeWebRequest request,
    CancelToken? cancel,
  ) async {
    final client = HttpClient();
    void abort() {
      if (cancel?.isCanceled ?? false) client.close(force: true);
    }

    cancel?.addListener(abort);
    try {
      final httpRequest = await client.getUrl(request.uri);
      request.headers.forEach(httpRequest.headers.set);
      final response = await httpRequest.close();
      final body = await response.transform(utf8.decoder).join();
      if (cancel?.isCanceled ?? false) throw SearchException('已取消');
      return FreeWebResponse(statusCode: response.statusCode, body: body);
    } on SocketException catch (error) {
      if (cancel?.isCanceled ?? false) throw SearchException('已取消');
      throw SearchException('网络错误：${error.message}');
    } finally {
      cancel?.removeListener(abort);
      client.close();
    }
  }
}
