import 'assistant_service.dart';
import 'persona.dart';
import 'reading_context.dart';

class UnconfiguredAssistantService implements AssistantService {
  const UnconfiguredAssistantService();

  @override
  bool get isConfigured => false;

  @override
  Stream<String> translate(String text, {required String targetLang}) {
    return _notConfigured();
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) {
    return _notConfigured();
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) {
    return _notConfigured();
  }

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    return _notConfigured();
  }

  Stream<String> _notConfigured() {
    return Stream<String>.error(const AssistantNotConfiguredException());
  }
}
