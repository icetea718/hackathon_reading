import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/chat_repository.dart';
import 'package:hackathon_reading/distill/llm/llm_client.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';
import 'package:hackathon_reading/features/search/search_shell.dart';
import 'package:hackathon_reading/search/search_config.dart';
import 'package:hackathon_reading/search/search_hit.dart';
import 'package:hackathon_reading/search/search_provider.dart';

/// Streams [chunks] and honours cancellation, so the stop button is testable.
class SlowClient implements LlmClient {
  SlowClient(this.chunks, {this.gap = const Duration(milliseconds: 50)});

  final List<String> chunks;
  final Duration gap;
  final List<List<LlmMessage>> calls = [];
  bool canceled = false;

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    calls.add(messages);
    for (final chunk in chunks) {
      if (cancel?.isCanceled ?? false) {
        canceled = true;
        return;
      }
      await Future<void>.delayed(gap);
      if (cancel?.isCanceled ?? false) {
        canceled = true;
        return;
      }
      yield chunk;
    }
  }

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async =>
      '{}';

  @override
  void dispose() {}
}

class InstantClient implements LlmClient {
  InstantClient(this.reply);

  final String reply;
  final List<List<LlmMessage>> calls = [];

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    calls.add(messages);
    yield reply;
  }

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async =>
      '{}';

  @override
  void dispose() {}
}

/// Returns canned hits, or throws once [failWith] is set.
class FakeSearch implements SearchProvider {
  FakeSearch({this.hits = const [], this.failWith});

  List<SearchHit> hits;
  Object? failWith;
  final List<String> queries = [];

  @override
  String get id => 'fake';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchHit>> search(
    String query, {
    int count = 5,
    CancelToken? cancel,
  }) async {
    queries.add(query);
    final failure = failWith;
    if (failure != null) throw failure;
    return hits;
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpShell(
    WidgetTester tester, {
    required LlmClient client,
    LlmConfig config = const LlmConfig(
      baseUrl: 'https://api.test/v1',
      model: 'test-model',
      apiKey: 'sk-test',
    ),
    SearchProvider? search,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llmClientProvider.overrideWithValue(client),
          llmConfigProvider.overrideWith((ref) => config),
          searchConfigProvider.overrideWith(
            (ref) => const SearchConfig(provider: 'tavily', apiKey: 'tv-key'),
          ),
          if (search != null) webSearchProvider.overrideWithValue(search),
        ],
        child: const MaterialApp(home: SearchShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts the shell inside the test body so drift's stream-cancel timer
  /// runs before the framework checks for pending timers.
  Future<void> disposeShell(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }


  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('chat-input')), text);
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
  }

  // Drift's in-memory executor only advances while the fake clock is pumped, so
  // queries issued from the test body have to hop out to real async.
  Future<List<ChatThreadRow>> threadRows(WidgetTester tester) async {
    final rows = await tester.runAsync(
      () => ChatThreadRepository(db).watchAll().first,
    );
    return rows!;
  }

  Future<List<ChatMessageRow>> messagesOf(
    WidgetTester tester,
    String threadId,
  ) async {
    final rows = await tester.runAsync(
      () => ChatMessageRepository(db).list(threadId),
    );
    return rows!;
  }

  testWidgets('sends a question and persists both sides of the exchange',
      (tester) async {
    final client = InstantClient('ok');
    await pumpShell(tester, client: client);

    await send(tester, '你好');

    expect(find.text('你好'), findsWidgets);
    expect(find.text('ok'), findsOneWidget);

    final threads = await threadRows(tester);
    expect(threads, hasLength(1));
    expect(threads.single.title, '你好');

    final rows = await messagesOf(tester, threads.single.id);
    expect(rows.map((row) => row.role), ['user', 'assistant']);
    expect(rows.first.content, '你好');
    expect(rows.last.content, 'ok');
    expect(rows.last.status, 'complete');

    // The system prompt opened the request.
    expect(client.calls.single.first.role, LlmRole.system);
    expect(client.calls.single.last.content, '你好');
    await disposeShell(tester);
  });

  testWidgets('stop keeps what arrived and marks the row interrupted',
      (tester) async {
    final client = SlowClient(['第一段', '第二段', '第三段']);
    await pumpShell(tester, client: client);

    await tester.enterText(find.byKey(const Key('chat-input')), '讲个长故事');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump(const Duration(milliseconds: 80));

    await tester.tap(find.byKey(const Key('chat-stop')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final threads = await threadRows(tester);
    final rows = await messagesOf(tester, threads.single.id);

    expect(client.canceled, isTrue);
    expect(rows.last.status, 'interrupted');
    expect(rows.last.content, '第一段');
    expect(find.byKey(const Key('chat-stop')), findsNothing);
    await disposeShell(tester);
  });

  testWidgets('an unconfigured model blocks sending and offers settings',
      (tester) async {
    await pumpShell(
      tester,
      client: InstantClient('nope'),
      config: LlmConfig.defaults,
    );

    expect(find.text('去设置'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byKey(const Key('chat-input'))).enabled,
      isFalse,
    );
    await disposeShell(tester);
  });

  testWidgets('a reply left streaming by a crash is marked interrupted',
      (tester) async {
    final threadId = await tester.runAsync(() async {
      final thread = await ChatThreadRepository(db).create(title: '旧对话');
      await ChatMessageRepository(db).append(
        threadId: thread.id,
        role: 'assistant',
        content: '半句话',
        status: 'streaming',
      );
      return thread.id;
    });

    await pumpShell(tester, client: InstantClient('ok'));
    await tester.pump(const Duration(milliseconds: 50));

    final rows = await messagesOf(tester, threadId!);
    expect(rows.single.status, 'interrupted');
    await disposeShell(tester);
  });

  testWidgets('web results ground the prompt and show up as sources',
      (tester) async {
    final client = InstantClient('见 flutter.dev');
    final search = FakeSearch(
      hits: const [
        SearchHit(
          title: 'Flutter 文档',
          snippet: '跨平台 UI 工具包',
          source: 'flutter.dev',
          url: 'https://flutter.dev/',
        ),
      ],
    );
    await pumpShell(tester, client: client, search: search);

    await tester.tap(find.byKey(const Key('chat-web-toggle')));
    await tester.pumpAndSettle();
    await send(tester, 'flutter 是什么');

    expect(search.queries, ['flutter 是什么']);
    expect(client.calls.single.first.content, contains('https://flutter.dev/'));
    expect(find.byKey(const Key('chat-sources')), findsOneWidget);

    final threads = await threadRows(tester);
    final rows = await messagesOf(tester, threads.single.id);
    expect(rows.last.sourcesJson, contains('flutter.dev'));
    await disposeShell(tester);
  });

  testWidgets('a failed search still answers and offers a retry',
      (tester) async {
    final client = InstantClient('ok');
    final search = FakeSearch(failWith: SearchException('boom'));
    await pumpShell(tester, client: client, search: search);

    await tester.tap(find.byKey(const Key('chat-web-toggle')));
    await tester.pumpAndSettle();
    await send(tester, '最近的新闻');

    expect(find.text('ok'), findsOneWidget);
    expect(find.byKey(const Key('chat-degraded')), findsOneWidget);

    search
      ..failWith = null
      ..hits = const [
        SearchHit(title: '某新闻', snippet: '摘要', source: 'news.test', url: 'https://news.test/a'),
      ];
    await tester.tap(find.byKey(const Key('chat-retry')));
    await tester.pumpAndSettle();

    expect(search.queries.length, 2);
    expect(find.byKey(const Key('chat-degraded')), findsNothing);
    expect(find.byKey(const Key('chat-sources')), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('a narrow window keeps the history in a drawer', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpShell(tester, client: InstantClient('ok'));

    expect(find.byKey(const Key('chat-sidebar')), findsNothing);
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-sidebar')), findsOneWidget);
    await disposeShell(tester);
  });
}
