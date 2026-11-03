import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/assistant/unconfigured_assistant_service.dart';

void main() {
  const service = UnconfiguredAssistantService();
  const context = ReadingContext(
    bookTitle: '围城',
    author: '钱钟书',
    chapterTitle: '第一章',
    chapterText: '正文',
    selectedText: '方鸿渐',
  );

  test('reports itself as not configured', () {
    expect(service.isConfigured, isFalse);
  });

  test('translate emits a not-configured error', () {
    expect(
      service.translate('hello', targetLang: 'zh'),
      emitsError(
        isA<AssistantNotConfiguredException>().having(
          (error) => error.toString(),
          'message',
          '未配置 AI 服务',
        ),
      ),
    );
  });

  test('explain emits a not-configured error', () {
    expect(
      service.explain('方鸿渐', context: context),
      emitsError(isA<AssistantNotConfiguredException>()),
    );
  });

  test('summarizeChapter emits a not-configured error', () {
    expect(
      service.summarizeChapter(context),
      emitsError(isA<AssistantNotConfiguredException>()),
    );
  });

  test('chat emits a not-configured error', () {
    expect(
      service.chat(
        context,
        const [
          ChatMessage(role: ChatRole.user, content: '这本书讲了什么？'),
        ],
        '继续说说第一章',
      ),
      emitsError(isA<AssistantNotConfiguredException>()),
    );
  });
}
