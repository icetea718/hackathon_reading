import 'reading_context.dart';

abstract class AssistantService {
  bool get isConfigured;

  Stream<String> translate(String text, {required String targetLang});

  Stream<String> explain(String text, {required ReadingContext context});

  Stream<String> summarizeChapter(ReadingContext context);

  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage,
  );
}

class AssistantNotConfiguredException implements Exception {
  const AssistantNotConfiguredException();

  @override
  String toString() => '未配置 AI 服务';
}
