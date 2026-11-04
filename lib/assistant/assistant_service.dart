import 'persona.dart';
import 'reading_context.dart';

abstract class AssistantService {
  bool get isConfigured;

  Stream<String> translate(String text, {required String targetLang});

  Stream<String> explain(String text, {required ReadingContext context});

  Stream<String> summarizeChapter(ReadingContext context);

  /// Talks with the reader in [persona]'s voice.
  ///
  /// Only the voice changes between modes: [context] and [history] are sent
  /// untouched, so switching mid-conversation keeps every earlier turn.
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  });
}

class AssistantNotConfiguredException implements Exception {
  const AssistantNotConfiguredException();

  @override
  String toString() => '未配置 AI 服务';
}
