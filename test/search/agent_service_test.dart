import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/repositories/companion_chat_repository.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/search/agent_service.dart';
import 'package:coread/search/book_context.dart';
import 'package:coread/search/book_memory.dart';
import 'package:coread/search/search_hit.dart';

import '../support/fake_llm_client.dart';

void main() {
  LlmMessage user(String text) => LlmMessage(LlmRole.user, text);
  LlmMessage assistant(String text) => LlmMessage(LlmRole.assistant, text);

  test('puts the system prompt first and the question last', () async {
    final client = FakeLlmClient(reply: 'ok');
    final service = SearchAgentService(client: client);

    final chunks = await service.send(
      history: [user('之前的问题'), assistant('之前的回答')],
      userText: '今天天气怎么样',
      cancel: CancelToken(),
    ).toList();

    expect(chunks.join(), 'ok');
    final messages = client.lastMessages;
    expect(messages.first.role, LlmRole.system);
    expect(messages.first.content, searchSystemPrompt);
    expect(messages.last.role, LlmRole.user);
    expect(messages.last.content, '今天天气怎么样');
    expect(messages.first.content, isNot(contains('检索结果')));
  });

  test('injects every hit, with its url, into the system prompt', () async {
    final client = FakeLlmClient();
    final service = SearchAgentService(client: client);

    await service.send(
      history: const [],
      userText: 'flutter 3.47 有什么变化',
      hits: const [
        SearchHit(
          title: 'Flutter 3.47 release notes',
          snippet: 'Impeller 改进。',
          source: 'flutter.dev',
          url: 'https://flutter.dev/release/3-47',
        ),
        SearchHit(
          title: 'Dart 3.13',
          snippet: '新的格式化器。',
          source: 'dart.dev',
          url: 'https://dart.dev/blog/3-13',
        ),
      ],
      cancel: CancelToken(),
    ).toList();

    final system = client.lastMessages.first.content;
    expect(system, contains('https://flutter.dev/release/3-47'));
    expect(system, contains('https://dart.dev/blog/3-13'));
    expect(system, contains('Flutter 3.47 release notes'));
    expect(system, contains('Impeller 改进。'));
  });

  test('drops the oldest turns once the history gets long', () async {
    final client = FakeLlmClient();
    final service = SearchAgentService(client: client);
    final long = 'x' * 900;

    await service.send(
      history: [
        for (var i = 0; i < 30; i++)
          i.isEven ? user('$i$long') : assistant('$i$long'),
      ],
      userText: '现在是哪个问题',
      cancel: CancelToken(),
    ).toList();

    final messages = client.lastMessages;
    // 1 system + kept turns + 1 question.
    expect(messages.length, lessThan(32));
    expect(messages.last.content, '现在是哪个问题');

    final kept = messages.sublist(1, messages.length - 1);
    expect(kept, isNotEmpty);
    expect(
      kept.fold<int>(0, (sum, message) => sum + message.content.length),
      lessThanOrEqualTo(SearchAgentService.maxHistoryChars),
    );
    // The newest turns survive; the oldest ones go first.
    expect(kept.last.content, startsWith('29'));
  });

  test('a picked book puts its brief and quotes in the system prompt',
      () async {
    final client = FakeLlmClient();
    final service = SearchAgentService(client: client);

    await service.send(
      history: const [],
      userText: '冰层有多厚',
      book: const BookContext(
        bookId: 'b1',
        title: '瓦尔登湖',
        author: '梭罗',
        brief: '一句话：一个人在林子里住两年。\n第 2 章 冬天的湖',
        distilled: true,
        excerpts: [
          BookExcerpt(
            chapterIndex: 1,
            chapterTitle: '冬天的湖',
            text: '冰层有二十二英寸厚。',
          ),
        ],
      ),
      cancel: CancelToken(),
    ).toList();

    final system = client.lastMessages.first.content;
    expect(system, contains(searchBookHeader));
    expect(system, contains('《瓦尔登湖》'));
    expect(system, contains('一个人在林子里住两年。'));
    expect(system, contains('第 2 章 冬天的湖'));
    expect(system, contains('冰层有二十二英寸厚。'));
    // The model is told to cite the chapter rather than invent quotes.
    expect(system, contains('不要编造原文'));
  });

  test('the reader notes and companion digest join the system prompt',
      () async {
    final client = FakeLlmClient();
    final service = SearchAgentService(client: client);

    await service.send(
      history: const [],
      userText: '我划线的地方在讲什么',
      memory: const BookMemory(
        bookTitle: '瓦尔登湖',
        bookmarks: [
          BookAnnotationEntry(label: '第 2 章 冬天的湖', text: ''),
        ],
        highlights: [
          BookAnnotationEntry(label: '第 1 章 经济', text: '一个人住'),
        ],
        notes: [
          BookAnnotationEntry(label: '第 3 章 湖', text: '这里很安静'),
        ],
        companionThreads: [],
        companionDigest: CompanionDigest(
          text: '【经济】读者：为什么住湖边？ 助手：想试试。',
          threadIds: {'t1'},
        ),
      ),
      cancel: CancelToken(),
    ).toList();

    final system = client.lastMessages.first.content;
    expect(system, contains('【读者的标注与陪读记录】'));
    expect(system, contains('书签：'));
    expect(system, contains('第 2 章 冬天的湖'));
    expect(system, contains('高亮：'));
    expect(system, contains('一个人住'));
    expect(system, contains('笔记：'));
    expect(system, contains('这里很安静'));
    expect(system, contains('【陪读对话摘要】'));
    expect(system, contains('想试试'));
    // The model must not mistake the reader's own notes for the book's text.
    expect(system, contains('不是原文'));
  });

  test('an empty memory adds nothing to the prompt', () async {
    final client = FakeLlmClient();
    final service = SearchAgentService(client: client);

    await service.send(
      history: const [],
      userText: '你好',
      memory: const BookMemory(
        bookTitle: '瓦尔登湖',
        bookmarks: [],
        highlights: [],
        notes: [],
        companionThreads: [],
        companionDigest: CompanionDigest.empty,
      ),
      cancel: CancelToken(),
    ).toList();

    expect(
      client.lastMessages.first.content,
      isNot(contains('【读者的标注与陪读记录】')),
    );
  });

  test('a pre-cancelled request never reaches the client', () async {
    final client = FakeLlmClient();
    final service = SearchAgentService(client: client);
    final cancel = CancelToken()..cancel();

    final chunks = await service
        .send(history: const [], userText: '你好', cancel: cancel)
        .toList();

    expect(chunks, isEmpty);
    expect(client.calls, isEmpty);
  });
}
