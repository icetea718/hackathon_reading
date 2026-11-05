import 'dart:convert';

import '../distill/llm/llm_client.dart';
import '../domain/models/chapter.dart';
import 'book_context.dart';
import 'book_searcher.dart';

/// The two read-only actions the搜 shell may take inside the selected book.
///
/// [call] never throws: every failure comes back as `{"error": "..."}` so the
/// model can decide whether to retry with other arguments or give up, instead
/// of the whole turn dying on a bad parameter.
class BookToolbox {
  BookToolbox({required this.book, required this.searcher});

  final BookContext book;
  final BookSearcher searcher;

  /// Longest chapter slice handed back by `get_chapter`.
  static const int maxChapterChars = 3000;

  /// Longest snippet handed back by `search_in_book`.
  static const int maxSnippetChars = 400;

  static const List<LlmToolSpec> specs = [
    LlmToolSpec(
      name: 'search_in_book',
      description: '在读者选中的这本书里检索原文片段。先用【蒸馏】判断可能在哪几章，'
          '再考虑填 chapter 缩小范围。返回按相关度排序的片段，每段带章号和字符偏移。',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '检索词或短句，2~12 字，一次只查一个点',
          },
          'chapter': {
            'type': 'integer',
            'description': '只查这一章（从 1 开始）。不填则查全书',
          },
          'limit': {
            'type': 'integer',
            'description': '返回几段，默认 3，最多 5',
          },
        },
        'required': ['query'],
      },
    ),
    LlmToolSpec(
      name: 'get_chapter',
      description: '读某一章的正文切片。用于确认检索到的片段前后文，或核对引文。',
      parameters: {
        'type': 'object',
        'properties': {
          'chapter': {'type': 'integer', 'description': '章号，从 1 开始'},
          'offset': {
            'type': 'integer',
            'description': '章内起始字符偏移，默认 0',
          },
          'max_chars': {
            'type': 'integer',
            'description': '最多返回多少字，默认 2000，上限 3000',
          },
        },
        'required': ['chapter'],
      },
    ),
  ];

  List<Chapter>? _chapters;

  /// Runs one tool call and returns the JSON text to put in a `tool` message.
  Future<String> call(String name, String argumentsJson) async {
    final args = _decode(argumentsJson);
    if (args == null) return _error('参数不是合法 JSON');

    switch (name) {
      case 'search_in_book':
        return _searchInBook(args);
      case 'get_chapter':
        return _getChapter(args);
      default:
        return _error('未知工具：$name');
    }
  }

  Future<String> _searchInBook(Map<String, Object?> args) async {
    final query = args['query'];
    if (query is! String || query.trim().isEmpty) return _error('缺少 query');

    final chapterNo = args['chapter'] is int ? args['chapter'] as int : null;
    final rawLimit = args['limit'];
    final limit = rawLimit is int ? rawLimit.clamp(1, 5) : 3;

    // An out-of-range chapter used to fall through the filter and come back as
    // "no hits", which reads exactly like "this book never mentions it" — the
    // model cannot tell a wrong chapter number from a real absence.
    if (chapterNo != null && _chapterAt(await _loadChapters(), chapterNo) == null) {
      return _error('第 $chapterNo 章不存在');
    }

    final result = await searcher.search(
      book.bookId,
      query,
      chapter: chapterNo == null ? null : chapterNo - 1,
      limit: limit,
    );

    return jsonEncode({
      'query': query,
      'chapter': chapterNo,
      'truncated': result.truncated,
      'hits': [
        for (final hit in result.hits)
          {
            'chapter': hit.chapterNo,
            'title': hit.chapterTitle,
            'offset': hit.offset,
            'score': hit.score,
            'text': _clip(hit.text, maxSnippetChars),
          },
      ],
    });
  }

  Future<String> _getChapter(Map<String, Object?> args) async {
    final chapterNo = args['chapter'];
    if (chapterNo is! int) return _error('缺少 chapter');

    final chapters = await _loadChapters();
    final chapter = _chapterAt(chapters, chapterNo);
    if (chapter == null) return _error('第 $chapterNo 章不存在');

    final text = await searcher.loadChapterText(book.bookId, chapter.index);
    if (text == null || text.trim().isEmpty) {
      return _error('第 $chapterNo 章没有正文');
    }

    var offset = args['offset'] is int ? args['offset'] as int : 0;
    if (offset < 0) offset = 0;
    if (offset > text.length) offset = text.length;

    final rawMax = args['max_chars'];
    final maxChars =
        rawMax is int ? rawMax.clamp(1, maxChapterChars) : 2000;

    return jsonEncode({
      'chapter': chapterNo,
      'title': chapter.title,
      'offset': offset,
      'text': _clip(text.substring(offset), maxChars),
    });
  }

  Future<List<Chapter>> _loadChapters() async =>
      _chapters ??= await searcher.loadChapters(book.bookId);

  static Chapter? _chapterAt(List<Chapter> chapters, int chapterNo) {
    for (final chapter in chapters) {
      if (chapter.index == chapterNo - 1) return chapter;
    }
    return null;
  }

  static Map<String, Object?>? _decode(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }

  static String _error(String message) => jsonEncode({'error': message});

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}
