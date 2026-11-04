import 'dart:async';

import 'assistant_service.dart';
import 'reading_context.dart';
import '../data/repositories/translation_cache_repository.dart';

/// Wraps a translator with a persistent cache so a passage is only ever sent to
/// the model or the public API once.
///
/// The cache is content addressed (SHA-256 of the source text + target
/// language), which means the same paragraph is reused no matter whether it was
/// translated from a selection popup or as part of a whole chapter.
class CachedTranslationService implements AssistantService {
  const CachedTranslationService({required this.inner, required this.cache});

  final AssistantService inner;
  final TranslationCacheStore cache;

  @override
  bool get isConfigured => inner.isConfigured;

  @override
  Stream<String> translate(String text, {required String targetLang}) async* {
    final cached = await _lookup(text, targetLang);
    if (cached != null && cached.isNotEmpty) {
      yield cached;
      return;
    }

    final buffer = StringBuffer();
    await for (final chunk in inner.translate(text, targetLang: targetLang)) {
      buffer.write(chunk);
      yield chunk;
    }

    final translated = buffer.toString();
    if (translated.isEmpty) return;
    unawaited(
      cache
          .save(text, targetLang: targetLang, translatedText: translated)
          .catchError((Object _) {}),
    );
  }

  Future<String?> _lookup(String text, String targetLang) async {
    try {
      return await cache.find(text, targetLang: targetLang);
    } catch (_) {
      // A broken cache must never block translation.
      return null;
    }
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) {
    return inner.explain(text, context: context);
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) {
    return inner.summarizeChapter(context);
  }

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage,
  ) {
    return inner.chat(context, history, userMessage);
  }
}
