# 免费联网搜索源（必应 RSS）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让「联网」支持两种源——原来的 Tavily（需 Key）与新增的免 Key 免费源（必应 RSS），点输入框下方的「联网」时弹面板选择，选择即持久化。

**Architecture:** 免费源是一个新的 `SearchProvider` 实现，走 `cn.bing.com/search?format=rss`，用已有的 `xml` 包解析；配置层用 `SearchConfig.requiresApiKey` 表达「哪些源需要 Key」；运行时由 `RoutingSearchProvider` 按当前配置把 `search()` 分发给具体实现；UI 层把 `SearchShell` 里的本地 bool 换成从配置派生的状态，chip 点开一个底部面板。

**Tech Stack:** Flutter 3.47 / Dart 3.13、Riverpod 3、`dart:io` HttpClient、`xml` ^7.1.0、Drift（测试用内存库）、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-04-free-web-search-design.md`

## Global Constraints

- 不新增任何 pub 依赖（HTTP 用 `dart:io`，解析用已有 `xml`）；不新增 HTTP 包。
- 既有 334 个测试必须保持全绿；每个任务结束时 `flutter analyze` 0 issue。
- 目标平台 Windows + Android，代码不得只用其中一端的 API。
- 存储键不变（`search.provider` / `search.apiKey`），不做数据迁移。
- 提交时只 `git add` 本任务涉及的路径，**禁止 `git add -A`**（工作树里有无关的 companion/TTS 改动）。
- 异常文案与 Tavily 保持一致：`联网搜索超时` / `网络错误：…` / `已取消` / `未配置联网搜索` / `HTTP {code}: …`。
- **Spec 偏差（已定，按此执行）**：spec §8.2 想在 `SearchProvider` 上加 `needsApiKey`。不这样做——接口加成员会波及 `test/` 里 4 个既有 fake 实现，而 `SearchConfig.requiresApiKey` 已能表达同一件事。Task 1 顺手把 spec 这段改掉。

## Review Focus

1. 必应返回的不是 RSS（HTML 报错页、空 body、截断的 XML）时：必须抛 `SearchException`，不能让 `FormatException`/`XmlParserException` 冒到 UI。
2. 连不上或超时：走既有的 20s 超时与 `SocketException` 文案，不能永久挂起。
3. `count` 传入 0 或负数：夹到合法范围，不能返回空或抛 `RangeError`。
4. 没配 Key 就想切到 Tavily：提示并且**不**改写当前源，不能静默变成 Tavily。
5. 配置是 `off` 但 `search()` 被调用：抛 `未配置联网搜索`，不能返回空数组（空数组会被当成「检索无结果」，掩盖配置错误）。

---

### Task 1: 配置层支持免费源

**Files:**
- Modify: `lib/search/search_config.dart`
- Modify: `docs/superpowers/specs/2026-11-04-free-web-search-design.md`（§8.2 措辞）
- Test: `test/search/search_config_test.dart`（新建）

**Interfaces:**
- Consumes: 无
- Produces: `SearchConfig.free == 'free'`；`bool get requiresApiKey`；`isConfigured` 对免费源恒为 true（只要 provider != off）

- [ ] **Step 1: 写失败的测试**

```dart
// test/search/search_config_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/settings_repository.dart';
import 'package:hackathon_reading/search/search_config.dart';

void main() {
  test('免费源不需要 Key，Tavily 需要', () {
    expect(const SearchConfig(provider: SearchConfig.free).isConfigured, isTrue);
    expect(const SearchConfig(provider: SearchConfig.free).isEnabled, isTrue);
    expect(const SearchConfig(provider: SearchConfig.free).requiresApiKey, isFalse);
    expect(const SearchConfig(provider: SearchConfig.tavily).requiresApiKey, isTrue);
    expect(const SearchConfig(provider: SearchConfig.tavily).isConfigured, isFalse);
    expect(const SearchConfig().isConfigured, isFalse);
  });

  test('provider = free 且带 key 时仍以免费源为准', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SearchConfigStore(SettingsRepository(db));

    await store.save(const SearchConfig(provider: SearchConfig.free, apiKey: ''));
    final restored = await store.load();

    expect(restored.provider, 'free');
    expect(restored.isEnabled, isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/search/search_config_test.dart`
Expected: FAIL — `SearchConfig.free` / `requiresApiKey` 未定义（编译错误）

- [ ] **Step 3: 实现**

在 `lib/search/search_config.dart` 常量区加 `static const free = 'free';`，并替换 `isConfigured`：

```dart
  /// Tavily 需要一个 Key；免 Key 的源返回 false。
  bool get requiresApiKey => provider == tavily;

  bool get isConfigured =>
      provider != off && (!requiresApiKey || apiKey.trim().isNotEmpty);
```

类注释里的 `'off' 或 'tavily'` 改为 `'off' | 'free' | 'tavily'`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/search/search_config_test.dart`
Expected: PASS（2 tests）

- [ ] **Step 5: 改 spec 措辞**

把 spec §8.2 整节替换为：

```markdown
### 8.2 Provider 契约

`SearchProvider` 接口不改（不在接口上加 `needsApiKey`，避免波及既有 fake）。是否需要 Key 由配置层表达：`SearchConfig.requiresApiKey`。
```

- [ ] **Step 6: 提交**

```bash
git add lib/search/search_config.dart test/search/search_config_test.dart docs/superpowers/specs/2026-11-04-free-web-search-design.md
git commit -m "feat(search): 配置层支持免 Key 的免费搜索源"
```

---

### Task 2: 免费源实现（必应 RSS）

**Files:**
- Create: `lib/search/url_host.dart`
- Create: `lib/search/free_web_search_provider.dart`
- Modify: `lib/search/tavily_search_provider.dart`（改用共享 `hostOf`，删掉私有 `_hostOf`）
- Test: `test/search/free_web_search_provider_test.dart`（新建）

**Interfaces:**
- Consumes: `SearchProvider` / `SearchHit` / `SearchException` / `CancelToken`
- Produces:
  - `String hostOf(String? url)`（`lib/search/url_host.dart`）
  - `class FreeWebRequest { const FreeWebRequest({required Uri uri, required Map<String, String> headers}); }`
  - `class FreeWebResponse { const FreeWebResponse({required int statusCode, required String body}); }`
  - `typedef FreeWebTransport = Future<FreeWebResponse> Function(FreeWebRequest request, CancelToken? cancel);`
  - `FreeWebSearchProvider({FreeWebTransport? transport})`，`id == 'free'`，`isConfigured == true`，静态 `endpoint = 'https://cn.bing.com/search'`、`defaultUrlTimeout = Duration(seconds: 20)`

- [ ] **Step 1: 写失败的测试**

```dart
// test/search/free_web_search_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/search/free_web_search_provider.dart';
import 'package:hackathon_reading/search/search_provider.dart';

const _rss = '''<?xml version="1.0" encoding="utf-8" ?>
<rss version="2.0"><channel><title>必应：AI news</title>
<item>
  <title>AI News | Latest</title>
  <link>https://www.artificialintelligence-news.com/</link>
  <description>AI News delivers the &lt;b&gt;latest&lt;/b&gt; updates.</description>
  <pubDate>周三, 04 11月 2026 08:39:00 GMT</pubDate>
</item>
<item>
  <title>每日 AI 资讯 - 猫目</title>
  <link>https://maomu.com/news</link>
  <description>从具身智能机器人到 AI 智能体手机。</description>
  <pubDate>周三, 04 11月 2026 10:05:00 GMT</pubDate>
</item>
<item>
  <title>TechCrunch</title>
  <link>https://techcrunch.com/category/artificial-intelligence/</link>
  <description>Read the latest.</description>
  <pubDate>not a date</pubDate>
</item>
</channel></rss>''';

void main() {
  final requests = <FreeWebRequest>[];

  FreeWebSearchProvider providerReturning(
    FreeWebResponse response, {
    Object? throws,
  }) {
    return FreeWebSearchProvider(
      transport: (request, cancel) async {
        requests.add(request);
        if (throws != null) throw throws;
        return response;
      },
    );
  }

  setUp(requests.clear);

  test('把 RSS 条目映射成 hits，source 取域名', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 200, body: _rss),
    );

    final hits = await provider.search('AI news');

    expect(hits, hasLength(3));
    expect(hits.first.title, 'AI News | Latest');
    expect(hits.first.url, 'https://www.artificialintelligence-news.com/');
    expect(hits.first.source, 'artificialintelligence-news.com');
    expect(hits.first.snippet, 'AI News delivers the latest updates.');
    expect(hits.first.publishedAt, '2026-11-04T08:39:00.000Z');
    expect(hits.last.publishedAt, isNull);

    final uri = requests.single.uri;
    expect(uri.host, 'cn.bing.com');
    expect(uri.queryParameters['q'], 'AI news');
    expect(uri.queryParameters['format'], 'rss');
  });

  test('count 夹到 1..10', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 200, body: _rss),
    );

    expect(await provider.search('x', count: 2), hasLength(2));
    expect(await provider.search('x', count: 0), hasLength(1));
    expect(await provider.search('x', count: 99), hasLength(3));
  });

  test('非 RSS 响应抛 SearchException', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 200, body: '<html>blocked</html>'),
    );

    await expectLater(
      provider.search('x'),
      throwsA(isA<SearchException>()),
    );
  });

  test('HTTP 500 带状态码', () async {
    final provider = providerReturning(
      const FreeWebResponse(statusCode: 500, body: 'oops'),
    );

    await expectLater(
      provider.search('x'),
      throwsA(
        isA<SearchException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', contains('HTTP 500')),
      ),
    );
  });

  test('网络错误与取消使用既有文案', () async {
    final offline = providerReturning(
      const FreeWebResponse(statusCode: 200, body: ''),
      throws: SearchException('网络错误：连接失败'),
    );
    await expectLater(offline.search('x'), throwsA(isA<SearchException>()));

    final canceled = providerReturning(
      const FreeWebResponse(statusCode: 200, body: _rss),
      throws: SearchException('已取消'),
    );
    await expectLater(
      canceled.search('x'),
      throwsA(
        isA<SearchException>()
            .having((e) => e.message, 'message', '已取消'),
      ),
    );
  });

  test('没有 item 时返回空列表', () async {
    final provider = providerReturning(
      const FreeWebResponse(
        statusCode: 200,
        body: '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>',
      ),
    );

    expect(await provider.search('x'), isEmpty);
  });

  test('免 Key 即已配置', () {
    final provider = FreeWebSearchProvider();
    expect(provider.id, 'free');
    expect(provider.isConfigured, isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/search/free_web_search_provider_test.dart`
Expected: FAIL — `free_web_search_provider.dart` 不存在（编译错误）

- [ ] **Step 3: 实现 `hostOf`**

```dart
// lib/search/url_host.dart
/// Host of [url] without a leading `www.`; empty when [url] is null/relative.
String hostOf(String? url) {
  if (url == null || url.isEmpty) return '';
  final host = Uri.tryParse(url)?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}
```

在 `tavily_search_provider.dart` 里删掉 `static String _hostOf`，改 import `url_host.dart` 并在 `_toHit` 里用 `hostOf(url)`；`grep -n _hostOf lib/` 应为空。

- [ ] **Step 4: 实现 `FreeWebSearchProvider`**

要点（签名已定，body 自行编写）：
- `search()` 用 `Uri.https(endpoint 的 host, '/search', {'q': query, 'format': 'rss'})` 组地址；`count.clamp(1, 10)`
- 请求头：`{'user-agent': <桌面 Chrome UA>, 'accept-language': 'zh-CN,zh;q=0.9'}`
- 传输层：`cancel?.addListener(abort)` → `client.close(force: true)`；`finally` 里 `removeListener` + `close()`；`SocketException` 转 `SearchException('网络错误：${e.message}')`；响应后若已取消抛 `已取消`
- 外层 `.timeout(defaultUrlTimeout, onTimeout: () => throw SearchException('联网搜索超时'))`
- 解析：`XmlDocument.parse(body)` 中所有 `item`；取 `title` / `link` / `description` / `pubDate` 的文本
  - `snippet`：先按 `<[^>]+>` 去掉标签（必应会插 `<b>`），再 `replaceAll(RegExp(r'\s+'), ' ').trim()`；实体由 xml 包解码
  - `publishedAt`：先试 `HttpDate.parse`，再试正则 `^[^,]+, (\d{1,2}) (\d{1,2})月 (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$` 组 `DateTime.utc`，都失败置 null；可解析时统一输出 `toIso8601String()`
  - `url`：`link` 为空时置 null；`source` 用 `hostOf`
- 文档节点的缺失（无 `item`、无 `pubDate`）一律容忍

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/search/free_web_search_provider_test.dart test/search/tavily_search_provider_test.dart`
Expected: PASS（免费源 7 tests + Tavily 5 tests）

- [ ] **Step 6: 提交**

```bash
git add lib/search/url_host.dart lib/search/free_web_search_provider.dart lib/search/tavily_search_provider.dart test/search/free_web_search_provider_test.dart
git commit -m "feat(search): 新增免 Key 的必应 RSS 搜索源"
```

---

### Task 3: 按配置分发到具体源

**Files:**
- Create: `lib/search/routing_search_provider.dart`
- Modify: `lib/app/providers.dart:139-177`（从 `searchConfigStoreProvider` 到 `searchProviderFactoryProvider`）
- Test: `test/search/routing_search_provider_test.dart`（新建）

**Interfaces:**
- Consumes: `SearchConfig.free`（Task 1）、`FreeWebSearchProvider`（Task 2）
- Produces: `RoutingSearchProvider({required SearchConfig Function() config, SearchProvider? free, SearchProvider? tavily})`；`id => config().provider`；`isConfigured => config().isConfigured`
- `webSearchProvider` 与 `searchProviderFactoryProvider` 都改为返回 `RoutingSearchProvider`

- [ ] **Step 1: 写失败的测试**

```dart
// test/search/routing_search_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/search/routing_search_provider.dart';
import 'package:hackathon_reading/search/search_config.dart';
import 'package:hackathon_reading/search/search_hit.dart';
import 'package:hackathon_reading/search/search_provider.dart';

class _Recorder implements SearchProvider {
  _Recorder(this.id);
  @override
  final String id;
  int calls = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<List<SearchHit>> search(String query, {int count = 5, CancelToken? cancel}) async {
    calls++;
    return [SearchHit(title: id, snippet: '', source: '', url: null)];
  }
}

void main() {
  test('免费配置走免费源，Tavily 配置走 Tavily', () async {
    final free = _Recorder('free');
    final tavily = _Recorder('tavily');
    var config = const SearchConfig(provider: SearchConfig.free, apiKey: '');
    final router = RoutingSearchProvider(
      config: () => config,
      free: free,
      tavily: tavily,
    );

    expect(router.isConfigured, isTrue);
    await router.search('q');
    expect(free.calls, 1);
    expect(tavily.calls, 0);

    config = const SearchConfig(provider: SearchConfig.tavily, apiKey: 'k');
    await router.search('q');
    expect(tavily.calls, 1);
  });

  test('配置为 off 时抛未配置，而不是返回空结果', () async {
    final router = RoutingSearchProvider(
      config: () => const SearchConfig(),
      free: _Recorder('free'),
      tavily: _Recorder('tavily'),
    );

    expect(router.isConfigured, isFalse);
    await expectLater(
      router.search('q'),
      throwsA(isA<SearchException>().having((e) => e.message, 'message', '未配置联网搜索')),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/search/routing_search_provider_test.dart`
Expected: FAIL — `routing_search_provider.dart` 不存在

- [ ] **Step 3: 实现**

`RoutingSearchProvider` 持有两个 delegate（默认惰性创建：`tavily ?? TavilySearchProvider(config: config)`、`free ?? FreeWebSearchProvider()`）。`search()`：`if (!config().isConfigured) throw SearchException('未配置联网搜索');` 然后 `config().provider == SearchConfig.free ? free : tavily`，原样转发 `query` / `count` / `cancel`。

`lib/app/providers.dart` 里：

```dart
final webSearchProvider = Provider<SearchProvider>((ref) {
  final source = ref.watch(searchConfigSourceProvider);
  return RoutingSearchProvider(config: () => source.value);
});

final searchProviderFactoryProvider = Provider<SearchProviderFactory>(
  (ref) => (config) => RoutingSearchProvider(config: () => config),
);
```

补 `import '../search/routing_search_provider.dart';`

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/search/routing_search_provider_test.dart`
Expected: PASS（2 tests）

- [ ] **Step 5: 提交**

```bash
git add lib/search/routing_search_provider.dart lib/app/providers.dart test/search/routing_search_provider_test.dart
git commit -m "feat(search): 按配置把检索分发给 Tavily 或免费源"
```

---

### Task 4: 选择面板

**Files:**
- Create: `lib/features/search/search_source_sheet.dart`
- Test: `test/features/search_source_sheet_test.dart`（新建）

**Interfaces:**
- Produces:
  - `enum SearchSource { off, free, tavily }`，带 `String get searchProvider`（映射到 `SearchConfig.off/free/tavily`）
  - `Future<SearchSource?> showSearchSourceSheet(BuildContext context, {required SearchConfig config})`
  - 键：`search-source-sheet`、`search-source-off`、`search-source-free`、`search-source-tavily`

- [ ] **Step 1: 写失败的测试**

```dart
// test/features/search_source_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/search/search_source_sheet.dart';
import 'package:hackathon_reading/search/search_config.dart';

void main() {
  Future<SearchSource?> openSheet(WidgetTester tester, SearchConfig config) async {
    SearchSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          config: config,
          onPicked: (value) => picked = value,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('列出三个选项，当前项被标记', (tester) async {
    await openSheet(tester, const SearchConfig(provider: SearchConfig.free));
    expect(find.byKey(const Key('search-source-sheet')), findsOneWidget);
    expect(find.byKey(const Key('search-source-off')), findsOneWidget);
    expect(find.byKey(const Key('search-source-free')), findsOneWidget);
    expect(find.byKey(const Key('search-source-tavily')), findsOneWidget);
    expect(find.text('必应网页结果 · 免 Key · 偶尔不稳定'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('点免费源返回 free 并关闭面板', (tester) async {
    SearchSource? picked;
    await tester.pumpWidget(
      MaterialApp(home: _Opener(config: const SearchConfig(), onPicked: (v) => picked = v)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-source-free')));
    await tester.pumpAndSettle();

    expect(picked, SearchSource.free);
    expect(find.byKey(const Key('search-source-sheet')), findsNothing);
  });

  test('SearchSource 映射到配置 id', () {
    expect(SearchSource.off.searchProvider, SearchConfig.off);
    expect(SearchSource.free.searchProvider, SearchConfig.free);
    expect(SearchSource.tavily.searchProvider, SearchConfig.tavily);
  });
}

class _Opener extends StatelessWidget {
  const _Opener({required this.config, required this.onPicked});

  final SearchConfig config;
  final ValueChanged<SearchSource?> onPicked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final picked = await showSearchSourceSheet(context, config: config);
            onPicked(picked);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/search_source_sheet_test.dart`
Expected: FAIL — 文件不存在

- [ ] **Step 3: 实现面板**

`showModalBottomSheet<SearchSource>`，`SafeArea` + `Column(mainAxisSize: min)`，顶部标题「联网搜索」+ 一行说明「选择检索来源；免费源不需要 API Key」。三个 `ListTile`：
- 关闭 / 副标题「只用模型自己的知识」
- 免费搜索 / 副标题「必应网页结果 · 免 Key · 偶尔不稳定」
- Tavily / 副标题「质量更好 · 需要在设置里填 API Key」

`config.provider` 命中的一项 `trailing: Icon(Icons.check)`。每项 `onTap: () => Navigator.pop(context, source)`。容器 `key: const Key('search-source-sheet')`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/features/search_source_sheet_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 5: 提交**

```bash
git add lib/features/search/search_source_sheet.dart test/features/search_source_sheet_test.dart
git commit -m "feat(search): 联网来源选择面板"
```

---

### Task 5: 接线到输入框与 shell

**Files:**
- Modify: `lib/features/search/chat_composer.dart`
- Modify: `lib/features/search/search_shell.dart`
- Test: `test/features/search_shell_test.dart`（扩展）

**Interfaces:**
- Consumes: `showSearchSourceSheet` / `SearchSource`（Task 4）、`SearchConfig.requiresApiKey`（Task 1）
- Produces: `ChatComposer` 的构造参数改为 `required String webSource`（当前源 id）与 `required VoidCallback onPickWebSource`；删掉 `webEnabled` / `webConfigured` / `onWebChanged`

- [ ] **Step 1: 写失败的测试**

在 `test/features/search_shell_test.dart` 里加一个可变配置的 store 与一个 helper：

```dart
class FakeSearchConfigStore implements SearchConfigStore {
  FakeSearchConfigStore([this.value = const SearchConfig()]);
  SearchConfig value;
  @override
  Future<SearchConfig> load() async => value;
  @override
  Future<void> save(SearchConfig config) async => value = config;
}
```

`pumpShell` 增加可选参数 `SearchConfig? searchConfig`（默认沿用现在的 tavily+key），并加 `overrideWithValue` 的 store：

```dart
    final store = FakeSearchConfigStore(searchConfig ?? const SearchConfig(provider: 'tavily', apiKey: 'tv-key'));
    // overrides 里追加：
    searchConfigStoreProvider.overrideWithValue(store),
    searchConfigProvider.overrideWith((ref) => ref.watch(searchConfigStoreProvider).load()),
```

三个新用例：

```dart
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
```

（`pumpShell` 的 `searchStore` 参数即上面的 `FakeSearchConfigStore`。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/search_shell_test.dart`
Expected: FAIL — `ChatComposer` 仍要求 `webEnabled`，面板键不存在

- [ ] **Step 3: 改 `ChatComposer`**

- 参数：`webSource`（`String`，当前 provider id）、`onPickWebSource`（`VoidCallback`）；删 `webEnabled` / `webConfigured` / `onWebChanged` 与 `_toggleWeb`
- `_WebChip` 改为：`active = webSource != SearchConfig.off`；`label` 文本 `off → '联网'`、`free → '联网·免费'`、`tavily → '联网·Tavily'`；`onSelected` 直接调 `onPickWebSource`
- 去掉 `SnackBar` 与 `webConfigured` 相关的 dead code

- [ ] **Step 4: 改 `SearchShell`**

- 删 `bool _webSearch` 与 `setState` 写入；改为在 `build` 里取配置：

```dart
    final search = ref.watch(searchConfigProvider).asData?.value ?? const SearchConfig();
    final webEnabled = search.isEnabled;
```

- 新增方法（用 `search` 的最新值）：

```dart
  Future<void> _pickWebSource() async {
    final current = ref.read(searchConfigProvider).asData?.value ?? const SearchConfig();
    final picked = await showSearchSourceSheet(context, config: current);
    if (!mounted || picked == null) return;
    if (picked == SearchSource.tavily && !current.copyWith(provider: SearchConfig.tavily).isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先在设置里填 Tavily API Key')),
      );
      return;
    }
    await ref.read(searchConfigStoreProvider).save(current.copyWith(provider: picked.searchProvider));
    ref.invalidate(searchConfigProvider);
  }
```

- `ChatComposer(...)` 改传 `webSource: search.provider`、`onPickWebSource: _pickWebSource`、`onSend: (text) => controller.send(text, webSearch: webEnabled)`
- **同时修掉 P0**：`_retry` 改成读同一来源——`void _retry(ChatController controller) { final enabled = ref.read(searchConfigProvider).asData?.value.isEnabled ?? false; controller.retry(webSearch: enabled); }`
- 若 `search_shell.dart` 尚缺 `search_config.dart` / `search_source_sheet.dart` 的 import 则补上

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/features/search_shell_test.dart`
Expected: PASS（既有用例 + 新增 3 个）

- [ ] **Step 6: 提交**

```bash
git add lib/features/search/chat_composer.dart lib/features/search/search_shell.dart test/features/search_shell_test.dart
git commit -m "feat(search): 联网 chip 改为选择来源，重试沿用同一配置"
```

---

### Task 6: 设置页

**Files:**
- Modify: `lib/features/settings/settings_page.dart:257-284`
- Test: `test/features/settings_page_test.dart`（扩展）

**Interfaces:**
- Consumes: `SearchConfig.free`（Task 1）
- Produces: 下拉新增「免费搜索（免 Key）」；`Tavily API Key` 输入框仅在 provider == tavily 时可见

- [ ] **Step 1: 写失败的测试**

在 `test/features/settings_page_test.dart` 的 `main` 里加：

```dart
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/settings_page_test.dart`
Expected: FAIL — 找不到「免费搜索（免 Key）」

- [ ] **Step 3: 实现**

- 下拉 `items` 插入 `DropdownMenuItem(value: SearchConfig.free, child: Text('免费搜索（免 Key）'))`（放在「关闭」与 Tavily 之间）
- 把 `search-api-key` 的 `TextField` 包成 `if (_searchProvider == SearchConfig.tavily) ...`，其 helper 文案不变
- `_testSearch()` 不动（工厂已按 config 路由）
- 注意：`test/features/settings_page_test.dart` 已有「选 Tavily 填 Key 再保存」的用例（用 `reveal(...)` + `tapAt(...)` 处理滚动）。改完 Key 框的可见性后，先跑一遍这个文件；若有既有用例依赖「provider=off 时 Key 框可见」，同步调整它，不要留着红。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/features/settings_page_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/features/settings/settings_page.dart test/features/settings_page_test.dart
git commit -m "feat(settings): 搜索服务支持免费源"
```

---

### Task 7: 全量回归

**Files:** 无新增

- [ ] **Step 1: 静态检查**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 全绿，总数 ≥ 338（原 334 + 新增）

- [ ] **Step 3: 手工冒烟（Windows）**

Run: `flutter run -d windows`
点「联网」→ 选「免费搜索」→ 发一个「最近 AI 有什么新闻」→ 确认流式回答里出现了网页来源、底部没有「本次未使用联网结果」；断网再发一次，确认出现灰条且对话不中断。

- [ ] **Step 4: 提交（若有冒烟期间的修补）**

```bash
git add -u lib test
git commit -m "fix(search): 免费源冒烟修补"
```
