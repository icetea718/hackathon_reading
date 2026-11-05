import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/settings_repository.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/distill/llm/llm_config.dart';
import 'package:coread/features/settings/settings_page.dart';
import 'package:coread/search/search_config.dart';
import 'package:coread/search/search_hit.dart';
import 'package:coread/search/search_provider.dart';
import 'package:coread/tts/tts_client.dart';
import 'package:coread/tts/tts_config.dart';

import '../support/fake_tts.dart';

class _FakeClient extends LlmClient {
  _FakeClient({this.failWith});

  final String? failWith;
  int calls = 0;

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async {
    calls++;
    if (failWith != null) throw LlmException(failWith!);
    return 'pong';
  }

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    yield 'pong';
  }

  @override
  void dispose() {}
}

class _FakeSearch implements SearchProvider {
  _FakeSearch({this.hits = const [], this.failWith});

  final List<SearchHit> hits;
  final String? failWith;
  int calls = 0;

  @override
  String get id => 'tavily';

  @override
  bool get isConfigured => true;

  @override
  Future<List<SearchHit>> search(
    String query, {
    int count = 5,
    CancelToken? cancel,
  }) async {
    calls++;
    if (failWith != null) throw SearchException(failWith!);
    return hits;
  }
}

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpPage(
    WidgetTester tester,
    LlmClient client, {
    TtsClient? ttsClient,
    void Function(TtsConfig config)? onTtsClientRequested,
    SearchProvider? searchProvider,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llmClientFactoryProvider.overrideWithValue((config) => client),
          if (ttsClient != null)
            ttsClientFactoryProvider.overrideWithValue((config) {
              onTtsClientRequested?.call(config);
              return ttsClient;
            }),
          if (searchProvider != null)
            searchProviderFactoryProvider.overrideWithValue(
              (config) => searchProvider,
            ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The form is taller than the viewport, so reach for widgets by scrolling.
  ///
  /// The page keeps growing (model, illustration, voice, search) and it swaps
  /// its body while a setting loads, so a single `scrollUntilVisible` can land
  /// on a frame with no scrollable at all. Drag in small steps — down first,
  /// then back up, since the caller may already sit past the section.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    Future<void> rewind() async {
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isEmpty) return;
      // The helper is reused for targets above the last one, so rewind first:
      // ListView disposes children scrolled out of its cache extent.
      final position = tester.state<ScrollableState>(scrollables.first).position;
      if (position.pixels > 0) {
        position.jumpTo(0);
        await tester.pumpAndSettle();
      }
    }

    Future<bool> dragUntil(Offset step) async {
      for (var i = 0; i < 40; i++) {
        if (finder.evaluate().isNotEmpty) return true;
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isEmpty) {
          await tester.pump(const Duration(milliseconds: 50));
          continue;
        }
        await tester.drag(scrollables.first, step);
        await tester.pumpAndSettle();
      }
      return finder.evaluate().isNotEmpty;
    }

    await rewind();
    if (!await dragUntil(const Offset(0, -160))) {
      await dragUntil(const Offset(0, 160));
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    // A lazy list builds a row slightly before it is fully on screen; nudge
    // until the centre of the target sits inside the window, otherwise the tap
    // lands on the bare render view and silently does nothing.
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 6; i++) {
      final y = tester.getRect(finder).center.dy;
      if (y > 24 && y < view.height - 24) break;
      await tester.drag(
        find.byType(Scrollable).first,
        Offset(0, y >= view.height - 24 ? -120 : 120),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).controller!.text;

  Future<void> fillTts(WidgetTester tester, {String? voice}) async {
    await reveal(tester, find.byKey(const Key('tts-base-url')));
    await tester.enterText(
      find.byKey(const Key('tts-base-url')),
      'http://127.0.0.1:9880',
    );
    if (voice != null) {
      await tester.enterText(find.byKey(const Key('tts-voice')), voice);
    }
  }

  testWidgets('tests the connection and saves the typed values', (tester) async {
    final fake = _FakeClient();
    await pumpPage(tester, fake);

    await tester.enterText(find.byKey(const Key('llm-api-key')), 'sk-test');
    await tester.enterText(find.byKey(const Key('llm-model')), 'custom-model');
    await tester.enterText(
      find.byKey(const Key('llm-base-url')),
      'http://localhost:8080/v1',
    );

    await tapAt(tester, find.text('测试连接'));

    expect(find.text('连接成功'), findsOneWidget);
    expect(fake.calls, 1);

    // Let the snack bar clear, otherwise it covers the button row.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tapAt(tester, find.text('保存'));

    final saved = await LlmConfigStore(SettingsRepository(db)).load();
    expect(saved.apiKey, 'sk-test');
    expect(saved.model, 'custom-model');
    expect(saved.baseUrl, 'http://localhost:8080/v1');
  });

  testWidgets('reports a failed connection attempt', (tester) async {
    await pumpPage(tester, _FakeClient(failWith: 'HTTP 401: bad key'));

    await tester.enterText(find.byKey(const Key('llm-api-key')), 'sk-bad');
    await tapAt(tester, find.text('测试连接'));

    expect(find.textContaining('连接失败'), findsOneWidget);
  });

  testWidgets('loads previously stored settings into the form', (tester) async {
    await LlmConfigStore(SettingsRepository(db)).save(
      const LlmConfig(
        baseUrl: 'https://example.test/v1',
        model: 'stored-model',
        apiKey: 'sk-stored',
      ),
    );

    await pumpPage(tester, _FakeClient());

    expect(find.text('https://example.test/v1'), findsOneWidget);
    expect(find.text('stored-model'), findsOneWidget);
  });

  testWidgets('saves the voice settings next to the model settings',
      (tester) async {
    await pumpPage(tester, _FakeClient());

    await fillTts(tester, voice: 'dfy');
    await tapAt(tester, find.byKey(const Key('tts-auto-speak')));
    await tapAt(tester, find.byKey(const Key('tts-enabled')));
    await tapAt(tester, find.text('保存'));

    final saved = await TtsConfigStore(SettingsRepository(db)).load();
    expect(saved.baseUrl, 'http://127.0.0.1:9880');
    expect(saved.voice, 'dfy');
    expect(saved.enabled, isFalse);
    expect(saved.autoSpeak, isTrue);
  });

  testWidgets('loads stored voice settings into the form', (tester) async {
    await TtsConfigStore(SettingsRepository(db)).save(
      const TtsConfig(
        baseUrl: 'http://192.168.1.5:9880',
        voice: 'female',
        speed: 1.25,
        volume: 0.8,
        autoSpeak: true,
      ),
    );

    await pumpPage(tester, _FakeClient());
    await reveal(tester, find.byKey(const Key('tts-base-url')));

    expect(textOf(tester, const Key('tts-base-url')), 'http://192.168.1.5:9880');
    expect(textOf(tester, const Key('tts-voice')), 'female');
    expect(textOf(tester, const Key('tts-speed')), '1.25');
  });

  testWidgets('the voice test reports a reachable service', (tester) async {
    await pumpPage(
      tester,
      _FakeClient(),
      ttsClient: FakeTtsClient(
        probeResult: const TtsProbe(ok: true, message: '语音服务可用：fake'),
      ),
    );

    await tapAt(tester, find.byKey(const Key('tts-test')));

    expect(find.textContaining('语音服务可用'), findsOneWidget);
  });

  testWidgets('the voice test pings the address that is on screen',
      (tester) async {
    TtsConfig? requested;
    await pumpPage(
      tester,
      _FakeClient(),
      ttsClient: FakeTtsClient(
        probeResult: const TtsProbe(
          ok: true,
          message: '语音服务可用：chino-tts（http://127.0.0.1:8766），默认音色 zhino',
        ),
      ),
      onTtsClientRequested: (config) => requested = config,
    );

    await reveal(tester, find.byKey(const Key('tts-base-url')));
    await tester.enterText(
      find.byKey(const Key('tts-base-url')),
      'http://127.0.0.1:8766',
    );
    await tapAt(tester, find.byKey(const Key('tts-test')));

    // Regression: the client used to be built from the provider snapshot,
    // which still held the defaults on the first save.
    expect(requested?.baseUrl, 'http://127.0.0.1:8766');
    expect(
      find.text('语音服务可用：chino-tts（http://127.0.0.1:8766），默认音色 zhino'),
      findsOneWidget,
    );
  });

  testWidgets('the voice test reports an unreachable service', (tester) async {
    await pumpPage(
      tester,
      _FakeClient(),
      ttsClient: FakeTtsClient(
        probeResult: const TtsProbe(
          ok: false,
          message: '连不上 http://127.0.0.1:8766（Connection refused）；先启动 chino-tts',
        ),
      ),
    );

    await tapAt(tester, find.byKey(const Key('tts-test')));

    // The page shows the probe's own sentence, so an online voice that works
    // without a local service is not labelled a blanket failure.
    expect(find.textContaining('连不上 http://127.0.0.1:8766'), findsOneWidget);
    expect(find.textContaining('先启动 chino-tts'), findsOneWidget);
  });

  testWidgets('the illustration section accepts any image-capable API',
      (tester) async {
    await pumpPage(tester, _FakeClient());

    await reveal(tester, find.text('插画（生图）'));

    expect(find.textContaining('必须使用火山方舟'), findsNothing);
    expect(
      find.textContaining('任意支持图片生成的 OpenAI 兼容接口'),
      findsOneWidget,
    );
  });

  testWidgets('saves the search settings and reports a probe hit',
      (tester) async {
    final search = _FakeSearch(
      hits: const [
        SearchHit(title: 'Ping', snippet: 'pong', source: 'example.com'),
      ],
    );
    await pumpPage(tester, _FakeClient(), searchProvider: search);

    await reveal(tester, find.byKey(const Key('search-provider')));
    await tester.tap(find.byKey(const Key('search-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tavily').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('search-api-key')), 'tvly-1');
    await tapAt(tester, find.byKey(const Key('search-test')));

    expect(find.text('搜索成功：1 条'), findsOneWidget);
    expect(search.calls, 1);

    final saved = await SearchConfigStore(SettingsRepository(db)).load();
    expect(saved.provider, SearchConfig.tavily);
    expect(saved.apiKey, 'tvly-1');
    expect(saved.isEnabled, isTrue);
  });

  testWidgets('选免费搜索时隐藏 Tavily Key 并保存为 free', (tester) async {
    await pumpPage(tester, _FakeClient());

    await reveal(tester, find.byKey(const Key('search-provider')));
    await tester.tap(find.byKey(const Key('search-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('免费搜索（免 Key）').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-api-key')), findsNothing);

    await tapAt(tester, find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await SearchConfigStore(SettingsRepository(db)).load();
    expect(saved.provider, SearchConfig.free);
    expect(saved.isEnabled, isTrue);
  });

  testWidgets('the search probe reports a failure', (tester) async {
    await pumpPage(
      tester,
      _FakeClient(),
      searchProvider: _FakeSearch(failWith: 'HTTP 401: bad key'),
    );

    await tapAt(tester, find.byKey(const Key('search-test')));

    expect(find.textContaining('搜索失败'), findsOneWidget);
    expect(find.textContaining('HTTP 401'), findsOneWidget);
  });

  testWidgets('书内检索工具默认打开，关掉后立即落库', (tester) async {
    await pumpPage(tester, _FakeClient());

    await reveal(tester, find.byKey(const Key('settings-tools-switch')));

    final store = SearchConfigStore(SettingsRepository(db));
    expect(await store.toolsEnabled(), isTrue);

    await tapAt(tester, find.byKey(const Key('settings-tools-switch')));

    expect(await store.toolsEnabled(), isFalse);
  });

  testWidgets('模型报告不支持时开关下面有提示', (tester) async {
    await SearchConfigStore(SettingsRepository(db))
        .markToolsUnsupported('deepseek-chat');
    await pumpPage(tester, _FakeClient());

    await reveal(tester, find.byKey(const Key('settings-tools-switch')));

    expect(find.textContaining('当前模型报告不支持'), findsOneWidget);
  });

  testWidgets('把开关重新打开会清掉「不支持」的记忆', (tester) async {
    final store = SearchConfigStore(SettingsRepository(db));
    await store.markToolsUnsupported('deepseek-chat');
    await store.setToolsEnabled(false);
    await pumpPage(tester, _FakeClient());

    await reveal(tester, find.byKey(const Key('settings-tools-switch')));
    await tapAt(tester, find.byKey(const Key('settings-tools-switch')));

    expect(await store.toolsEnabled(), isTrue);
    expect(await store.isToolsUnsupported('deepseek-chat'), isFalse);
  });
}
