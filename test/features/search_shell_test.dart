import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/chat_repository.dart';
import 'package:coread/data/repositories/companion_chat_repository.dart';
import 'package:coread/distill/distill_digest.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/distill/llm/llm_config.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/domain/models/companion_chat.dart';
import 'package:coread/features/search/chat_controller.dart';
import 'package:coread/features/search/search_shell.dart';
import 'package:coread/search/book_context.dart';
import 'package:coread/search/companion_selection.dart';
import 'package:coread/search/search_config.dart';
import 'package:coread/search/search_hit.dart';
import 'package:coread/data/repositories/chapter_repository.dart';
import 'package:coread/data/repositories/settings_repository.dart';
import 'package:coread/search/book_memory.dart';
import 'package:coread/search/book_toolbox.dart';
import 'package:coread/search/search_step.dart';
import 'package:coread/search/tool_agent.dart';
import 'package:coread/search/search_provider.dart';

/// Streams [chunks] and honours cancellation, so the stop button is testable.
class SlowClient extends LlmClient {
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

class InstantClient extends LlmClient {
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

/// In-memory stand-in for the settings-backed search config, so a test can
/// switch sources the way the source sheet does.
class FakeSearchConfigStore implements SearchConfigStore {
  FakeSearchConfigStore([this.value = const SearchConfig()]);

  SearchConfig value;
  bool tools = true;
  final Set<String> unsupported = {};

  @override
  Future<SearchConfig> load() async => value;

  @override
  Future<void> save(SearchConfig config) async => value = config;

  @override
  Future<bool> toolsEnabled() async => tools;

  @override
  Future<void> setToolsEnabled(bool enabled) async => tools = enabled;

  @override
  Future<bool> isToolsUnsupported(String model) async =>
      unsupported.contains(model);

  @override
  Future<void> markToolsUnsupported(String model) async =>
      unsupported.add(model);
}

/// Fails after optionally yielding [partial], to exercise the error path.
class FailingClient extends LlmClient {
  FailingClient({this.partial = '', this.message = '模型炸了'});

  final String partial;
  final String message;
  int calls = 0;

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    calls++;
    if (partial.isNotEmpty) yield partial;
    throw LlmException(message);
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

/// Fails the first request and succeeds on the retry.
class FlakyClient extends LlmClient {
  FlakyClient({this.reply = '重试成功'});

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
    if (calls.length == 1) {
      yield '半句';
      throw LlmException('模型炸了');
    }
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

/// Stays in flight long enough for the user to press stop, then reports cancel.
class SlowSearch implements SearchProvider {
  SlowSearch({this.delay = const Duration(milliseconds: 200)});

  final Duration delay;
  final List<String> queries = [];
  bool canceled = false;

  @override
  String get id => 'slow';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchHit>> search(
    String query, {
    int count = 5,
    CancelToken? cancel,
  }) async {
    queries.add(query);
    await Future<void>.delayed(delay);
    canceled = cancel?.isCanceled ?? false;
    throw SearchException('已取消');
  }
}

/// Holds thread creation until [gate] completes, to force overlapping sends.
class SlowThreadRepository extends ChatThreadRepository {
  SlowThreadRepository(super.db);

  final Completer<void> gate = Completer<void>();

  @override
  Future<ChatThreadRow> create({String? title, String? bookId}) async {
    await gate.future;
    return super.create(title: title, bookId: bookId);
  }
}

/// Holds the history query until [gate] completes, to force a load/send race.
class SlowListMessageRepository extends ChatMessageRepository {
  SlowListMessageRepository(super.db);

  final Completer<void> gate = Completer<void>();

  @override
  Future<List<ChatMessageRow>> list(String threadId) async {
    await gate.future;
    return super.list(threadId);
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
    BookContextBuilder? book,
    FakeSearchConfigStore? searchStore,
    SearchToolAgent? tools,
    bool realSearchStore = false,
  }) async {
    // The product default is "not online yet"; cases that want retrieval say so.
    final store = searchStore ?? FakeSearchConfigStore(const SearchConfig());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llmClientProvider.overrideWithValue(client),
          llmConfigProvider.overrideWith((ref) => config),
          if (!realSearchStore)
            searchConfigStoreProvider.overrideWithValue(store),
          searchConfigProvider.overrideWith(
            (ref) => ref.watch(searchConfigStoreProvider).load(),
          ),
          if (search != null) webSearchProvider.overrideWithValue(search),
          if (book != null) bookContextBuilderProvider.overrideWithValue(book),
          if (tools != null)
            searchToolAgentProvider.overrideWithValue(tools),
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

  /// A book in the library, optionally with chapter text to search.
  Future<void> seedBook(WidgetTester tester, {bool withText = true}) async {
    final book = Book(
      id: 'b1',
      title: '瓦尔登湖',
      author: '梭罗',
      format: BookFormat.epub,
      sourcePath: '/books/walden.epub',
      addedAt: DateTime(2026, 1, 1),
    );
    await tester.runAsync(() => BookRepository(db).upsert(book));
    if (!withText) return;
    await tester.runAsync(
      () => ChapterRepository(db).replaceForBook('b1', const [
        Chapter(
          id: 'c0',
          bookId: 'b1',
          index: 0,
          title: '经济',
          startOffset: 0,
          endOffset: 24,
          contentText: '冬天的湖结了二十二英寸厚的冰。',
        ),
      ]),
    );
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
    await pumpShell(
      tester,
      client: client,
      search: search,
      searchStore: FakeSearchConfigStore(
        const SearchConfig(provider: SearchConfig.tavily, apiKey: 'tv-key'),
      ),
    );

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
    await pumpShell(
      tester,
      client: client,
      search: search,
      searchStore: FakeSearchConfigStore(
        const SearchConfig(provider: SearchConfig.tavily, apiKey: 'tv-key'),
      ),
    );

    await send(tester, '最近的新闻');

    expect(find.text('ok'), findsOneWidget);
    expect(find.byKey(const Key('chat-degraded')), findsOneWidget);
    expect(find.text('最近的新闻'), findsOneWidget);
    final beforeThreads = await threadRows(tester);
    expect(
      await messagesOf(tester, beforeThreads.single.id),
      hasLength(2),
    );

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
    expect(find.text('最近的新闻'), findsOneWidget);
    final afterThreads = await threadRows(tester);
    expect(
      await messagesOf(tester, afterThreads.single.id),
      hasLength(2),
    );
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

  testWidgets('the picked book grounds the prompt and the reply is markdown',
      (tester) async {
    final book = Book(
      id: 'b1',
      title: '瓦尔登湖',
      author: '梭罗',
      format: BookFormat.epub,
      sourcePath: '/books/walden.epub',
      addedAt: DateTime(2026, 1, 1),
    );
    final client = InstantClient('## 小结\n\n> 冰层有二十二英寸厚。\n\n（第 2 章）');

    await pumpShell(
      tester,
      client: client,
      book: BookContextBuilder(
        loadBook: (id) async => id == book.id ? book : null,
        loadChapters: (id) async => const [
          Chapter(
            id: 'c0',
            bookId: 'b1',
            index: 0,
            title: '经济',
            startOffset: 0,
            endOffset: 0,
            contentText: '',
          ),
          Chapter(
            id: 'c1',
            bookId: 'b1',
            index: 1,
            title: '冬天的湖',
            startOffset: 0,
            endOffset: 0,
            contentText: '',
          ),
        ],
        loadChapterText: (id, index) async =>
            index == 1 ? '冬天的湖结了二十二英寸厚的冰。' : null,
        digests: _DigestSource(
          const DistillDigest(
            oneLiner: '一个人在林子里住两年。',
            gists: {1: '湖边冬天的冰层厚度。'},
          ),
        ),
      ),
    );
    await tester.runAsync(() => BookRepository(db).upsert(book));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-book')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-option-b1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-book-chip')), findsOneWidget);

    await send(tester, '冰层多厚');

    final system = client.calls.single.first.content;
    expect(system, contains('【正在读的书】'));
    expect(system, contains('一个人在林子里住两年。'));
    expect(system, contains('冬天的湖结了二十二英寸厚的冰。'));
    expect(system, contains('不要编造原文'));

    // Markdown, not raw markers.
    expect(find.textContaining('小结', findRichText: true), findsOneWidget);
    expect(find.textContaining('##', findRichText: true), findsNothing);
    await disposeShell(tester);
  });

  void setWide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Book shelfBook(String id, String title) {
    return Book(
      id: id,
      title: title,
      author: '',
      format: BookFormat.epub,
      sourcePath: '/books/$id.epub',
      addedAt: DateTime(2026, 1, 1),
    );
  }

  Future<void> pickBook(WidgetTester tester, String bookId) async {
    await tester.tap(find.byKey(const Key('chat-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('book-option-$bookId')));
    await tester.pumpAndSettle();
  }

  testWidgets('a question asked with a book picked is archived under it',
      (tester) async {
    await pumpShell(tester, client: InstantClient('ok'));
    await tester.runAsync(() => BookRepository(db).upsert(shelfBook('b1', '瓦尔登湖')));
    await tester.pumpAndSettle();

    await pickBook(tester, 'b1');
    await send(tester, '冰层多厚');

    final threads = await threadRows(tester);
    expect(threads.single.bookId, 'b1');
    await disposeShell(tester);
  });

  testWidgets('the book memory shortcut appears only with a book picked',
      (tester) async {
    await pumpShell(tester, client: InstantClient('ok'));

    expect(find.byKey(const Key('search-book-memory')), findsNothing);

    await tester.runAsync(
      () => BookRepository(db).upsert(shelfBook('b1', '瓦尔登湖')),
    );
    await tester.pumpAndSettle();
    await pickBook(tester, 'b1');

    expect(find.byKey(const Key('search-book-memory')), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('unchecked companion threads stay out of the prompt',
      (tester) async {
    final client = InstantClient('ok');
    final seeded = await tester.runAsync(() async {
      await BookRepository(db).upsert(shelfBook('b1', '瓦尔登湖'));
      final chats = CompanionChatRepository(db);
      final kept = await chats.createThread(
        bookId: 'b1',
        chapterIndex: 0,
        chapterTitle: '经济',
        title: '保留',
      );
      await chats.appendMessage(
        threadId: kept.id,
        role: CompanionRole.user,
        content: '保留的那句话',
      );
      final dropped = await chats.createThread(
        bookId: 'b1',
        chapterIndex: 1,
        chapterTitle: '湖',
        title: '去掉',
      );
      await chats.appendMessage(
        threadId: dropped.id,
        role: CompanionRole.user,
        content: '不该出现的那句话',
      );
      return (kept: kept.id, dropped: dropped.id);
    });

    await pumpShell(tester, client: client);
    await pickBook(tester, 'b1');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchShell)),
    );
    container
        .read(companionSelectionProvider('b1').notifier)
        .setSelection({seeded!.kept});

    await send(tester, '冰层多厚');

    expect(client.calls, isNotEmpty);
    final system = client.calls.single.first.content;
    expect(system, contains('保留的那句话'));
    expect(system, isNot(contains('不该出现的那句话')));
    await disposeShell(tester);
  });

  testWidgets('picking a book switches the sidebar to that book history',
      (tester) async {
    setWide(tester);
    await tester.runAsync(() async {
      final repo = ChatThreadRepository(db);
      final loose = await repo.create(title: '未选书的对话');
      await ChatMessageRepository(db).append(
        threadId: loose.id,
        role: 'user',
        content: '书架外的问题',
      );
      await repo.create(title: '书里的旧问题', bookId: 'b1');
      final latest = await repo.create(title: '书里的新问题', bookId: 'b1');
      await ChatMessageRepository(db).append(
        threadId: latest.id,
        role: 'user',
        content: '书里最新的提问',
      );
      await repo.create(title: '另一本书的对话', bookId: 'b2');
      await BookRepository(db).upsert(shelfBook('b1', '瓦尔登湖'));
    });
    await pumpShell(tester, client: InstantClient('ok'));

    expect(find.text('未选书的对话'), findsOneWidget);

    await pickBook(tester, 'b1');

    expect(find.text('书里的新问题'), findsOneWidget);
    expect(find.text('书里的旧问题'), findsOneWidget);
    expect(find.text('未选书的对话'), findsNothing);
    expect(find.text('另一本书的对话'), findsNothing);
    expect(find.text('书里最新的提问'), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('clearing the book returns to the threads with no book',
      (tester) async {
    setWide(tester);
    await tester.runAsync(() async {
      final repo = ChatThreadRepository(db);
      final loose = await repo.create(title: '未选书的对话');
      await ChatMessageRepository(db).append(
        threadId: loose.id,
        role: 'user',
        content: '书架外的问题',
      );
      await repo.create(title: '书里的新问题', bookId: 'b1');
      await BookRepository(db).upsert(shelfBook('b1', '瓦尔登湖'));
    });
    await pumpShell(tester, client: InstantClient('ok'));

    await pickBook(tester, 'b1');
    expect(find.text('书里的新问题'), findsOneWidget);

    await tester.tap(find.byTooltip('取消引用这本书'));
    await tester.pumpAndSettle();

    expect(find.text('未选书的对话'), findsOneWidget);
    expect(find.text('书里的新问题'), findsNothing);
    expect(find.text('书架外的问题'), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('a new conversation keeps the picked book scope', (tester) async {
    setWide(tester);
    await pumpShell(tester, client: InstantClient('ok'));
    await tester.runAsync(() => BookRepository(db).upsert(shelfBook('b1', '瓦尔登湖')));
    await tester.pumpAndSettle();

    await pickBook(tester, 'b1');
    await tester.tap(find.byKey(const Key('sidebar-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-book-chip')), findsOneWidget);

    await send(tester, '新问题');

    final threads = await threadRows(tester);
    expect(threads.single.title, '新问题');
    expect(threads.single.bookId, 'b1');
    await disposeShell(tester);
  });

  test('a retrieval failure that is not SearchException still finishes',
      () async {
    final search = FakeSearch(failWith: Exception('socket closed'));
    final client = InstantClient('ok');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmClientProvider.overrideWithValue(client),
        webSearchProvider.overrideWithValue(search),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(
      chatControllerProvider(ChatController.newThreadKey).notifier,
    );
    await controller.send('你好', webSearch: true);

    final state = container.read(
      chatControllerProvider(ChatController.newThreadKey),
    );
    expect(state.streaming, isFalse);
    expect(state.degraded, isTrue);
    expect(state.messages.last.content, 'ok');

    final threads = await ChatThreadRepository(db).watchAll().first;
    final rows = await ChatMessageRepository(db).list(threads.single.id);
    expect(rows.last.status, 'complete');
  });

  test('overlapping sends create only one thread', () async {
    final threads = SlowThreadRepository(db);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chatThreadRepositoryProvider.overrideWithValue(threads),
        llmClientProvider.overrideWithValue(InstantClient('ok')),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(
      chatControllerProvider(ChatController.newThreadKey).notifier,
    );
    final first = controller.send('a');
    final second = controller.send('b');
    threads.gate.complete();
    await Future.wait([first, second]);

    final rows = await threads.watchAll().first;
    expect(rows, hasLength(1));
  });

  test('a send waits for the thread history to load', () async {
    final thread = await ChatThreadRepository(db).create(title: '旧');
    await ChatMessageRepository(db).append(
      threadId: thread.id,
      role: 'user',
      content: '旧问题',
    );
    await ChatMessageRepository(db).append(
      threadId: thread.id,
      role: 'assistant',
      content: '旧回答',
    );

    final messages = SlowListMessageRepository(db);
    final client = InstantClient('新回答');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chatMessageRepositoryProvider.overrideWithValue(messages),
        llmClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(chatControllerProvider(thread.id).notifier);
    final sending = controller.send('新问题');
    messages.gate.complete();
    await sending;

    expect(
      client.calls.single.map((message) => message.content),
      contains('旧问题'),
    );
  });

  testWidgets('an LLM failure shows an error and retries in place',
      (tester) async {
    final client = FlakyClient();
    await pumpShell(tester, client: client);

    await send(tester, '问题');

    expect(find.byKey(const Key('chat-error')), findsOneWidget);
    expect(find.textContaining('模型炸了'), findsOneWidget);
    expect(find.text('半句'), findsOneWidget);
    expect(find.text('生成失败'), findsOneWidget);
    expect(find.byKey(const Key('chat-stop')), findsNothing);

    final threads = await threadRows(tester);
    final failedRows = await messagesOf(tester, threads.single.id);
    expect(failedRows.last.status, 'failed');

    await tester.tap(find.byKey(const Key('chat-error-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-error')), findsNothing);
    expect(find.text('重试成功'), findsOneWidget);
    expect(find.text('问题'), findsOneWidget);

    final rows = await messagesOf(tester, threads.single.id);
    expect(rows, hasLength(2));
    expect(rows.last.status, 'complete');
    expect(rows.last.content, '重试成功');
    await disposeShell(tester);
  });

  testWidgets('starting a new conversation mid-stream interrupts the old reply',
      (tester) async {
    setWide(tester);
    final client = SlowClient(
      ['第一段', '第二段'],
      gap: const Duration(milliseconds: 50),
    );
    await pumpShell(tester, client: client);

    await tester.enterText(find.byKey(const Key('chat-input')), '讲个故事');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump(const Duration(milliseconds: 80));

    final live = await threadRows(tester);
    await tester.tap(find.byKey(Key('sidebar-thread-${live.single.id}')));
    await tester.pump();
    expect(find.byKey(const Key('chat-stop')), findsOneWidget);
    expect(find.byKey(const Key('chat-send')), findsNothing);

    await tester.tap(find.byKey(const Key('sidebar-new')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final threads = await threadRows(tester);
    final rows = await messagesOf(tester, threads.single.id);
    expect(rows.last.status, 'interrupted');
    expect(rows.last.content, '第一段');
    expect(find.text('今天想查点什么？'), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('stopping during retrieval does not claim the search failed',
      (tester) async {
    final search = SlowSearch();
    await pumpShell(
      tester,
      client: InstantClient('ok'),
      search: search,
      searchStore: FakeSearchConfigStore(
        const SearchConfig(provider: SearchConfig.tavily, apiKey: 'tv-key'),
      ),
    );

    await tester.enterText(find.byKey(const Key('chat-input')), '新闻');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('chat-stop')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-degraded')), findsNothing);
    expect(find.byKey(const Key('chat-stop')), findsNothing);

    final threads = await threadRows(tester);
    final rows = await messagesOf(tester, threads.single.id);
    expect(rows.last.status, 'interrupted');
    await disposeShell(tester);
  });

  test('touch moves a thread to the top of the history', () async {
    final repo = ChatThreadRepository(db);
    final older = await repo.create(title: '旧对话');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final newer = await repo.create(title: '较新的对话');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.touch(older.id);

    final rows = await repo.watchAll().first;
    expect(rows.first.id, older.id);
    expect(rows.first.updatedAt.isAfter(newer.updatedAt), isTrue);
  });

  test('a sent answer advances the thread timestamp', () async {
    final thread = await ChatThreadRepository(db).create(title: '旧对话');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmClientProvider.overrideWithValue(InstantClient('ok')),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(chatControllerProvider(thread.id).notifier);
    await controller.send('新问题');

    final rows = await ChatThreadRepository(db).watchAll().first;
    expect(rows.single.id, thread.id);
    expect(rows.single.updatedAt.isAfter(thread.updatedAt), isTrue);
  });

  testWidgets('sources survive reopening a saved thread', (tester) async {
    setWide(tester);
    final search = FakeSearch(hits: const [
      SearchHit(
        title: '旧来源',
        snippet: '摘要',
        source: 'old.test',
        url: 'https://old.test/a',
      ),
    ]);
    await pumpShell(
      tester,
      client: InstantClient('ok'),
      search: search,
      searchStore: FakeSearchConfigStore(
        const SearchConfig(provider: SearchConfig.tavily, apiKey: 'tv-key'),
      ),
    );
    await send(tester, '旧新闻');

    expect(find.byKey(const Key('chat-sources')), findsOneWidget);
    final threads = await threadRows(tester);
    final id = threads.single.id;

    await tester.tap(find.byKey(const Key('sidebar-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-sources')), findsNothing);

    await tester.tap(find.byKey(Key('sidebar-thread-$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-sources')), findsOneWidget);
    expect(find.text('旧来源'), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('deleting the active thread resets the transcript',
      (tester) async {
    setWide(tester);
    await pumpShell(tester, client: InstantClient('ok'));
    await send(tester, '要删掉的问题');

    final threads = await threadRows(tester);
    final id = threads.single.id;
    expect(find.byKey(Key('sidebar-thread-$id')), findsOneWidget);
    expect(find.byKey(Key('sidebar-time-$id')), findsOneWidget);

    await tester.tap(find.byTooltip('删除对话'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('sidebar-thread-$id')), findsNothing);
    expect(find.text('今天想查点什么？'), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('the search header shows a single 搜 label', (tester) async {
    await pumpShell(tester, client: InstantClient('ok'));

    expect(find.text('搜'), findsOneWidget);
    expect(find.byKey(const Key('search-mode-search')), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('the empty state offers no canned prompts', (tester) async {
    await pumpShell(tester, client: InstantClient('ok'));

    expect(find.text('今天想查点什么？'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('最近 AI 领域有什么值得关注的事？'), findsNothing);
    expect(find.text('帮我对比一下 Flutter 和 React Native'), findsNothing);
    expect(find.text('解释一下什么是向量数据库'), findsNothing);
    await disposeShell(tester);
  });

  testWidgets('Enter sends the message', (tester) async {
    final client = InstantClient('ok');
    await pumpShell(tester, client: client);

    await tester.enterText(find.byKey(const Key('chat-input')), '回车发送');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('回车发送'), findsOneWidget);
    expect(await threadRows(tester), hasLength(1));
    expect(client.calls, hasLength(1));
    await disposeShell(tester);
  });

  testWidgets('点联网弹出面板，选免费源后发送会走检索', (tester) async {
    final search = FakeSearch();
    final store = FakeSearchConfigStore(const SearchConfig());
    await pumpShell(tester, client: InstantClient('ok'), search: search, searchStore: store);

    await tester.tap(find.byKey(const Key('chat-web-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-source-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-source-free')));
    await tester.pumpAndSettle();

    expect(store.value.provider, SearchConfig.free);
    expect(tester.widget<FilterChip>(find.byKey(const Key('chat-web-toggle'))).selected, isTrue);

    await send(tester, 'AI 新闻');
    expect(search.queries, ['AI 新闻']);
    await disposeShell(tester);
  });

  testWidgets('没填 Key 选 Tavily 只提示、不切换', (tester) async {
    final store = FakeSearchConfigStore(const SearchConfig());
    await pumpShell(tester, client: InstantClient('ok'), search: FakeSearch(), searchStore: store);

    await tester.tap(find.byKey(const Key('chat-web-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-source-tavily')));
    await tester.pumpAndSettle();

    expect(find.text('先在设置里填 Tavily API Key'), findsOneWidget);
    expect(store.value.provider, SearchConfig.off);
    await disposeShell(tester);
  });

  testWidgets('选关闭后发送不再检索', (tester) async {
    final search = FakeSearch();
    final store = FakeSearchConfigStore(const SearchConfig(provider: SearchConfig.free));
    await pumpShell(tester, client: InstantClient('ok'), search: search, searchStore: store);

    await tester.tap(find.byKey(const Key('chat-web-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-source-off')));
    await tester.pumpAndSettle();

    expect(store.value.provider, SearchConfig.off);
    await send(tester, '随便问问');
    expect(search.queries, isEmpty);
    await disposeShell(tester);
  });
  testWidgets('绑书且开着工具时走工具路径，步骤写进 stepsJson', (tester) async {
    final builder = _RecordingBookBuilder();
    final agent = _FakeToolAgent();
    await seedBook(tester);
    await pumpShell(
      tester,
      client: InstantClient('不该出现'),
      book: builder,
      tools: agent,
    );
    await tester.pumpAndSettle();
    await pickBook(tester, 'b1');

    await send(tester, '冬天湖上的冰有多厚？');

    expect(agent.calls, 1);
    expect(builder.includeExcerpts, [isFalse]);
    final threads = await threadRows(tester);
    final rows = await messagesOf(tester, threads.single.id);
    expect(rows.last.content, '答案');
    expect(rows.last.status, 'complete');
    expect(rows.last.stepsJson, contains('search_in_book'));
    expect(rows.last.stepsJson, contains('get_chapter'));
    await disposeShell(tester);
  });

  testWidgets('端点报告不支持工具时降级，记下按模型的不支持标记', (tester) async {
    final builder = _RecordingBookBuilder();
    final agent = _FakeToolAgent(unsupported: true);
    await seedBook(tester);
    await pumpShell(
      tester,
      client: InstantClient('旧答案'),
      book: builder,
      tools: agent,
      realSearchStore: true,
    );
    await tester.pumpAndSettle();
    await pickBook(tester, 'b1');

    await send(tester, '冬天湖上的冰有多厚？');

    final threads = await threadRows(tester);
    final rows = await messagesOf(tester, threads.single.id);
    expect(rows.last.content, '旧答案');
    expect(rows.last.status, 'complete');
    expect(rows.last.stepsJson, contains('notice'));
    // The fallback rebuilt the context the classic way, excerpts included.
    expect(builder.includeExcerpts, [isFalse, isTrue]);
    final flag = await tester.runAsync(
      () => SettingsRepository(db)
          .get(SearchConfig.toolsUnsupportedKey('test-model')),
    );
    expect(flag, 'true');
    await disposeShell(tester);
  });

  testWidgets('没有章节正文的书不进工具路径', (tester) async {
    final builder = _RecordingBookBuilder();
    final agent = _FakeToolAgent();
    await seedBook(tester, withText: false);
    await pumpShell(
      tester,
      client: InstantClient('摘要答案'),
      book: builder,
      tools: agent,
    );
    await tester.pumpAndSettle();
    await pickBook(tester, 'b1');

    await send(tester, '这本书讲了什么？');

    expect(agent.calls, 0);
    expect(builder.includeExcerpts, [isTrue]);
    final threads = await threadRows(tester);
    final rows = await messagesOf(tester, threads.single.id);
    expect(rows.last.content, '摘要答案');
    expect(rows.last.stepsJson, null);
    await disposeShell(tester);
  });
}

/// Records the shape of every context build, so a test can tell the tool path
/// (no excerpts) from the classic one.
class _RecordingBookBuilder extends BookContextBuilder {
  _RecordingBookBuilder()
      : super(
          loadBook: (id) async => null,
          loadChapters: (id) async => const [],
          loadChapterText: (id, index) async => null,
          digests: _DigestSource(null),
        );

  final List<bool> includeExcerpts = [];

  @override
  Future<BookContext?> build(
    String bookId, {
    String question = '',
    bool includeExcerpts = true,
    int? briefChars,
  }) async {
    this.includeExcerpts.add(includeExcerpts);
    return BookContext(
      bookId: bookId,
      title: '瓦尔登湖',
      author: '梭罗',
      brief: '一个人在林子里住了两年。',
      distilled: true,
    );
  }
}

/// Stands in for the ReAct loop: two tool steps then an answer, or the
/// unsupported-endpoint failure the controller has to fall back from.
class _FakeToolAgent extends SearchToolAgent {
  _FakeToolAgent({this.unsupported = false})
      : super(client: InstantClient('ignored'));

  final bool unsupported;
  int calls = 0;

  @override
  Future<ToolRunResult> run({
    required List<LlmMessage> history,
    required String userText,
    required BookContext book,
    required BookToolbox toolbox,
    BookMemory? memory,
    List<SearchHit> hits = const [],
    required CancelToken cancel,
    required TextSink onText,
    required StepSink onStep,
  }) async {
    calls++;
    if (unsupported) throw ToolUnsupportedException('no tools here');
    const steps = [
      SearchStep(
        tool: 'search_in_book',
        summary: '检索「冬天的湖」',
        chapters: [1],
        hits: 2,
        ms: 12,
      ),
      SearchStep(
        tool: 'get_chapter',
        summary: '读第 1 章',
        chapters: [1],
        hits: 0,
        ms: 8,
      ),
    ];
    for (final step in steps) {
      onStep(step);
    }
    onText('答案');
    return ToolRunResult(steps: steps, toolCalls: steps.length);
  }
}

class _DigestSource implements DistillDigestSource {
  _DigestSource(this.digest);

  final DistillDigest? digest;

  @override
  Future<DistillDigest?> load(String bookId) async => digest;
}
