import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'assistant_service.dart';
import 'persona.dart';
import 'reading_context.dart';
import 'translation_exception.dart';
import 'translation_segmenter.dart';
import 'unconfigured_assistant_service.dart';

/// Sends one piece of text to a translation provider.
abstract class TranslationBackend {
  Future<String> translate(String text, {required String langPair});
}

/// Calls the public MyMemory API, which needs no API key.
class MyMemoryBackend implements TranslationBackend {
  MyMemoryBackend({
    this.client,
    this.timeout = const Duration(seconds: 20),
  });

  final HttpClient? client;
  final Duration timeout;

  @override
  Future<String> translate(String text, {required String langPair}) async {
    final client = this.client ?? (HttpClient()..connectionTimeout = timeout);
    try {
      final uri = Uri.https(
        'api.mymemory.translated.net',
        '/get',
        {'q': text, 'langpair': langPair},
      );
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'hackathon_reading');
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(
            timeout,
          );
      return parseMyMemoryBody(body);
    } on TranslationException {
      rethrow;
    } on TimeoutException {
      throw const TranslationException('翻译请求超时，请检查网络后重试');
    } on SocketException {
      throw const TranslationException('网络连接失败，请检查网络后重试');
    } on HttpException {
      throw const TranslationException('翻译服务暂时不可用，请稍后重试');
    } finally {
      if (this.client == null) client.close(force: true);
    }
  }
}

/// Extracts the translated text out of a MyMemory response body.
String parseMyMemoryBody(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const TranslationException('翻译服务返回了无法解析的内容');
  }
  if (decoded is! Map) {
    throw const TranslationException('翻译服务返回了无法解析的内容');
  }

  final data = decoded['responseData'];
  final translated = data is Map ? data['translatedText'] : null;
  final text = translated is String ? translated.trim() : '';
  final status = decoded['responseStatus'];
  final details = '${decoded['responseDetails'] ?? ''}';

  if (text.startsWith('MYMEMORY WARNING')) {
    throw const TranslationException('今日免费翻译额度已用完，请明天再试');
  }
  if (status is int && status != 200) {
    if (details.toUpperCase().contains('DISTINCT LANGUAGES')) {
      throw const TranslationException('原文已是中文，无需翻译');
    }
    if (details.toUpperCase().contains('QUERY LENGTH LIMIT')) {
      throw const TranslationException('这段文字太长，无法一次翻译');
    }
    throw TranslationException(
      details.isEmpty ? '翻译失败（状态码 $status）' : '翻译失败：$details',
    );
  }
  if (text.isEmpty) {
    throw const TranslationException('翻译服务没有返回译文，请稍后重试');
  }
  return text;
}

/// [AssistantService] whose translation ability is backed by a free public
/// translation API. The AI-only methods stay unavailable until a real model is
/// wired in.
class MyMemoryTranslator implements AssistantService {
  MyMemoryTranslator({
    TranslationBackend? backend,
    TranslationSegmenter? segmenter,
    this.requestInterval = const Duration(milliseconds: 150),
  })  : _backend = backend ?? MyMemoryBackend(),
        _segmenter = segmenter ?? TranslationSegmenter();

  final TranslationBackend _backend;
  final TranslationSegmenter _segmenter;

  /// Pause between two requests so a long chapter does not trip the free quota.
  final Duration requestInterval;

  @override
  bool get isConfigured => true;

  @override
  Stream<String> translate(String text, {required String targetLang}) async* {
    final segments = _segmenter.split(text);
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      // Segments are deltas of the final text, so paragraphs are separated
      // here rather than in the UI (an LLM stream must not be re-chunked).
      final prefix = index == 0 ? '' : '\n';
      if (isPredominantlyChinese(segment)) {
        yield '$prefix$segment';
        continue;
      }
      if (index > 0) await Future<void>.delayed(requestInterval);
      final translated = await _backend.translate(
        segment,
        langPair: 'autodetect|$targetLang',
      );
      yield '$prefix$translated';
    }
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) {
    return const UnconfiguredAssistantService().explain(text, context: context);
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) {
    return const UnconfiguredAssistantService().summarizeChapter(context);
  }

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    return const UnconfiguredAssistantService().chat(
      context,
      history,
      userMessage,
      persona: persona,
    );
  }
}
