import 'dart:convert';

/// One citable piece of material behind an answer.
///
/// Web results carry [url]; future "search inside my library" results carry
/// [locatorJson] instead. The chat UI and the persisted `sourcesJson` only ever
/// need these fields, so both kinds of search share one shape.
class SearchHit {
  const SearchHit({
    required this.title,
    required this.snippet,
    required this.source,
    this.url,
    this.locatorJson,
    this.publishedAt,
  });

  final String title;
  final String snippet;

  /// Domain of a web result, or the book title for a library hit.
  final String source;
  final String? url;

  /// `{'bookId', 'chapterIndex', 'offset'}` for library hits; null for web.
  final String? locatorJson;
  final String? publishedAt;

  Map<String, dynamic> toJson() => {
        'title': title,
        'snippet': snippet,
        'source': source,
        if (url != null) 'url': url,
        if (locatorJson != null) 'locator': locatorJson,
        if (publishedAt != null) 'publishedAt': publishedAt,
      };

  factory SearchHit.fromJson(Map<String, dynamic> json) => SearchHit(
        title: json['title'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
        source: json['source'] as String? ?? '',
        url: json['url'] as String?,
        locatorJson: json['locator'] as String?,
        publishedAt: json['publishedAt'] as String?,
      );

  static List<SearchHit> listFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map<String, dynamic>) SearchHit.fromJson(entry),
    ];
  }

  static String listToJson(List<SearchHit> hits) =>
      jsonEncode([for (final hit in hits) hit.toJson()]);

  @override
  String toString() => 'SearchHit($title, $source)';
}
