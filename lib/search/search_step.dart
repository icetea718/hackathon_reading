import 'dart:convert';

/// One thing the model did with a tool, kept short enough to store per message.
///
/// Deliberately holds no原文: the step row under an answer is a receipt, not an
/// archive.
class SearchStep {
  const SearchStep({
    required this.tool,
    required this.summary,
    required this.chapters,
    required this.hits,
    required this.ms,
  });

  final String tool;
  final String summary;

  /// 1-based chapter numbers the tool touched.
  final List<int> chapters;
  final int hits;
  final int ms;

  Map<String, Object?> toJson() => {
        'tool': tool,
        'summary': summary,
        'chapters': chapters,
        'hits': hits,
        'ms': ms,
      };

  static String listToJson(List<SearchStep> steps) =>
      jsonEncode([for (final step in steps) step.toJson()]);

  /// Lenient on purpose: a message written by an older build must still render.
  static List<SearchStep> listFromJson(String? json) {
    if (json == null || json.trim().isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];

    final steps = <SearchStep>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final chapters = item['chapters'];
      steps.add(
        SearchStep(
          tool: item['tool'] is String ? item['tool'] as String : '',
          summary: item['summary'] is String ? item['summary'] as String : '',
          chapters: chapters is List
              ? [
                  for (final chapter in chapters)
                    if (chapter is int) chapter,
                ]
              : const [],
          hits: item['hits'] is int ? item['hits'] as int : 0,
          ms: item['ms'] is int ? item['ms'] as int : 0,
        ),
      );
    }
    return steps;
  }
}
