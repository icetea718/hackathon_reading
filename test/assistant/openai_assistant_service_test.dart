import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/openai_assistant_service.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/distill/llm/llm_client.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';

import '../support/fake_llm_client.dart';

void main() {
  const context = ReadingContext(
    bookTitle: '活着',
    author: '余华',
    chapterTitle: '第一章',
    chapterText: '福贵牵着老牛走在田埂上。',
    selectedText: '福贵牵着老牛',
  );

  LlmConfig configured() => const LlmConfig(
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
        apiKey: 'sk-test',
      );

  test('isConfigured follows the supplied config', () {
    final client = FakeLlmClient();
    final service = OpenAiAssistantService(
      client: client,
      config: configured,
    );
    expect(service.isConfigured, isTrue);

    final unconfigured = OpenAiAssistantService(
      client: client,
      config: () => LlmConfig.defaults,
    );
    expect(unconfigured.isConfigured, isFalse);
  });

  test('every method throws while unconfigured', () {
    final service = OpenAiAssistantService(
      client: FakeLlmClient(),
      config: () => LlmConfig.defaults,
    );

    expect(
      () => service.translate('hi', targetLang: '中文'),
      throwsA(isA<AssistantNotConfiguredException>()),
    );
    expect(
      () => service.explain('hi', context: context),
      throwsA(isA<AssistantNotConfiguredException>()),
    );
    expect(
      () => service.summarizeChapter(context),
      throwsA(isA<AssistantNotConfiguredException>()),
    );
    expect(
      () => service.chat(context, const [], '这一章讲了什么？'),
      throwsA(isA<AssistantNotConfiguredException>()),
    );
  });

  test('chat sends book context, history, then the user message', () async {
    final client = FakeLlmClient(reply: '福贵在讲自己的过去。');
    final service = OpenAiAssistantService(
      client: client,
      config: configured,
    );

    final reply = await service.chat(
      context,
      const [
        ChatMessage(role: ChatRole.user, content: '你好'),
        ChatMessage(role: ChatRole.assistant, content: '你好，我在。'),
      ],
      '这一章讲了什么？',
    ).toList();

    expect(reply, ['福贵在讲自己的过去。']);
    final messages = client.lastMessages;
    expect(messages.first.role, LlmRole.system);
    expect(messages.first.content, contains('活着'));
    expect(messages.first.content, contains('余华'));
    expect(messages.first.content, contains('福贵牵着老牛走在田埂上。'));

    expect(messages[1].role, LlmRole.user);
    expect(messages[1].content, '你好');
    expect(messages[2].role, LlmRole.assistant);
    expect(messages.last.role, LlmRole.user);
    expect(messages.last.content, '这一章讲了什么？');
  });

  test('chat tells the model which page the reader is on', () async {
    const paged = ReadingContext(
      bookTitle: '活着',
      chapterTitle: '第一章',
      chapterText: '前后的正文。',
      chapterPage: 3,
      chapterPageEnd: 4,
      chapterPageCount: 20,
      bookPage: 42,
      bookPageTotal: 300,
      currentPageText: '这一页的正文。',
    );
    final client = FakeLlmClient(reply: '好的');
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.chat(paged, const [], '这一页讲了什么？').toList();

    final system = client.lastMessages.first.content;
    expect(system, contains('第 3–4 / 20 页'));
    expect(system, contains('全书第 42 / 300 页'));
    expect(system, contains('【读者正在看的这一页】'));
    expect(system, contains('这一页的正文。'));
  });

  test('a single page reports one page number', () async {
    const paged = ReadingContext(
      bookTitle: '活着',
      chapterPage: 3,
      chapterPageCount: 20,
    );
    final client = FakeLlmClient(reply: '好的');
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.chat(paged, const [], '这一页讲了什么？').toList();

    final system = client.lastMessages.first.content;
    expect(system, contains('读者当前位置：第 3 / 20 页'));
    expect(system, isNot(contains('–')));
  });

  test('chat guards the page from spoilers and puts it first', () async {
    const paged = ReadingContext(
      bookTitle: '活着',
      chapterTitle: '第一章',
      chapterText: '本章内容。',
      chapterPage: 3,
      chapterPageCount: 20,
      currentPageText: '这一页的正文。',
      bookBrief: '全书梗概。',
    );
    final client = FakeLlmClient(reply: '好的');
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.chat(paged, const [], '这一页讲了什么？').toList();

    final system = client.lastMessages.first.content;
    expect(system, contains('【剧透限制】'));
    expect(system, contains('当前页之后'));
    final page = system.indexOf('【读者正在看的这一页】');
    expect(page, greaterThan(0));
    expect(page, lessThan(system.indexOf('【全书蒸馏】')));
    expect(page, lessThan(system.indexOf('【当前章节内容】')));
  });

  test('allowing spoilers drops the restriction', () async {
    const paged = ReadingContext(
      bookTitle: '活着',
      chapterTitle: '第一章',
      chapterText: '本章内容。',
      chapterPage: 3,
      chapterPageCount: 20,
      currentPageText: '这一页的正文。',
      allowSpoilers: true,
    );
    final client = FakeLlmClient(reply: '好的');
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.chat(paged, const [], '后面发生了什么？').toList();

    final system = client.lastMessages.first.content;
    expect(system, isNot(contains('【剧透限制】')));
    expect(system, contains('允许剧透'));
  });

  test('summarizeChapter asks for a summary of this chapter', () async {
    final client = FakeLlmClient(reply: '摘要');
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.summarizeChapter(context).toList();

    final prompt = client.lastMessages.last.content;
    expect(prompt, contains('总结'));
    expect(prompt, contains('第一章'));
  });

  test('translate uses the selected text and target language', () async {
    final client = FakeLlmClient(reply: 'Fu Gui led the old ox');
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.translate(context.selectedText, targetLang: 'English').toList();

    final messages = client.lastMessages;
    expect(messages.last.content, contains('English'));
    expect(messages.last.content, contains('福贵牵着老牛'));
  });

  test('explain uses the selected text within the book context', () async {
    final client = FakeLlmClient(reply: '这是开篇');
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.explain(context.selectedText, context: context).toList();

    final messages = client.lastMessages;
    expect(messages.first.content, contains('活着'));
    expect(messages.last.content, contains('福贵牵着老牛'));
  });

  test('streams replies rather than buffering them', () async {
    final client = FakeLlmClient();
    final service = OpenAiAssistantService(client: client, config: configured);

    await service.summarizeChapter(context).toList();

    expect(client.streamed.single, isTrue);
  });

  test('chat folds the prior-chapter memory into the system prompt', () async {
    final client = FakeLlmClient(reply: '后来家道中落。');
    final service = OpenAiAssistantService(client: client, config: configured);
    const withMemory = ReadingContext(
      bookTitle: '活着',
      chapterTitle: '第三章',
      chapterText: '现在的正文。',
      companionMemory: '【第一章】读者：福贵是谁？ 助手：地主家的少爷。',
    );

    await service.chat(withMemory, const [], '后来呢？').toList();

    expect(client.lastMessages.first.content, contains('【此前章节的对话纪要】'));
    expect(client.lastMessages.first.content, contains('地主家的少爷'));
  });
}
