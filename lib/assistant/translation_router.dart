import 'assistant_service.dart';
import 'persona.dart';
import 'reading_context.dart';
import 'unconfigured_assistant_service.dart';

/// Routes translation to the configured model and falls back to a free public
/// API when no model is set up.
///
/// The two backends expect different language descriptions: the model receives
/// a human readable name ("中文"), while the public API needs an ISO code
/// ("zh-CN"). The router hides that difference from the UI.
class TranslationRouter implements AssistantService {
  const TranslationRouter({required this.preferred, required this.fallback});

  final AssistantService? preferred;
  final AssistantService fallback;

  @override
  bool get isConfigured => true;

  bool get _hasModel => preferred?.isConfigured ?? false;

  @override
  Stream<String> translate(String text, {required String targetLang}) {
    final model = preferred;
    if (model != null && _hasModel) {
      return model.translate(text, targetLang: languageName(targetLang));
    }
    return fallback.translate(text, targetLang: targetLang);
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) {
    return _assistant.explain(text, context: context);
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) {
    return _assistant.summarizeChapter(context);
  }

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    return _assistant.chat(context, history, userMessage, persona: persona);
  }

  AssistantService get _assistant {
    final model = preferred;
    if (model != null && _hasModel) return model;
    return const UnconfiguredAssistantService();
  }
}

/// Turns an ISO language code into the name a model prompt understands.
String languageName(String code) {
  return switch (code) {
    'zh' || 'zh-CN' || 'zh-Hans' => '中文',
    'en' || 'en-US' => '英文',
    'ja' || 'ja-JP' => '日文',
    'ko' || 'ko-KR' => '韩文',
    _ => code,
  };
}
