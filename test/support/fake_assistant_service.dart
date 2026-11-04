import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/persona.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';

/// Test double that replays [chunks] for every translation request.
class FakeAssistantService implements AssistantService {
  FakeAssistantService({
    this.chunks = const ['译文'],
    this.translateText,
    this.error,
    this.isConfigured = true,
  });

  final List<String> chunks;
  final String Function(String source)? translateText;
  final Object? error;
  final List<String> translatedSources = [];

  @override
  final bool isConfigured;

  @override
  Stream<String> translate(String text, {required String targetLang}) async* {
    translatedSources.add(text);
    final failure = error;
    if (failure != null) throw failure;
    final translateText = this.translateText;
    if (translateText != null) {
      yield translateText(text);
      return;
    }
    for (final chunk in chunks) {
      yield chunk;
    }
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) {
    return const Stream.empty();
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) {
    return const Stream.empty();
  }

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    return const Stream.empty();
  }
}
