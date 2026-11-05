# 搜壳工具循环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让「搜」壳里绑定的书可以被模型用真 tool calling 检索，检索步骤显示在回答上方并落库，端点不支持时自动降级为今天的单轮预检索。

**Architecture:** 三段。`OpenAiLlmClient.completeTurn` 新增一条非流式的 tools 请求/响应通道；`SearchToolAgent` 在它之上跑 ReAct 循环（执行工具、补全 tool 消息、触顶收尾），最终答案仍交给现有 `streamChat` 流式输出；`chat_controller` 在构建书上下文**之前**分流，步骤 JSON 写进 `ChatMessages.stepsJson`。

**Tech Stack:** Flutter 3.47 / Dart 3.13、flutter_riverpod 3、drift 2.35（build_runner 生成）、`dart:io` HttpClient、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-05-book-tool-loop-design.md`

## Global Constraints

- 不新增依赖；`pubspec.yaml` 的 dependencies / dev_dependencies 都不动。
- `LlmClient.streamChat` 签名与实现不变；`completeTurn` 必须在抽象类里带默认实现（`throw UnsupportedError`），因为 `test/support/fake_llm_client.dart` 等 6 个类 `implements LlmClient`。
- 现有 608 个测试保持全绿，`flutter analyze` 零问题。
- Drift 迁移 12 → 13，必须能升级老库；`chat_messages` 可能已被 v11 分支按新定义创建，所以加列前要用 `PRAGMA table_info` 判断。
- 目标平台 Windows 桌面 + Android；用户点「停止」必须立刻中断并保留已生成内容。
- 不假设端点支持 `parallel_tool_calls` / `strict` / 流式 tools；但必须假设一次响应可能返回多个 `tool_calls`。
- 章号对模型和 UI 一律 1 基，`ChapterRepository.getContent(bookId, chapterIndex)` 是 0 基，转换只许发生在 `BookToolbox` 内部。
- 工具参数、上限、文案里的魔数（4 步、6000 字、500 tokens、90 秒、200/100 窗口、8 章、3600 brief）全部按 spec 取值，不许自行调整。

## Review Focus

这些是 spec 隐含、但任何单个任务的测试都不会自动覆盖的输入；每条都已落到下述任务的测试里。

1. **没有可检索正文的书**（PDF、漫画：`chapters.contentText` 为空）被绑进搜壳提问——不能报错、不能进工具路径，行为与今天一致。
2. **模型给的 `arguments` 不是合法 JSON、缺必填字段、章号越界**——不能把异常抛到界面，必须变成 `{"error": ...}` 交回模型让它重试。
3. **用户在步骤行进动时点「停止」**——立刻停下，已生成内容与已完成步骤都保留，状态写 `interrupted`。
4. **重开会话**——步骤行与「当前模型不支持工具检索」的灰字都还在（都在 `stepsJson` 里）。
5. **300 章的大书**——章节地图截断但如实标注「共 N 章，此处只列 M 章」，检索只扫 8 章、不超过 40 万字，不会把整本书读进内存。

---

### Task 1: 消息模型与工具 schema

**Files:**
- Modify: `lib/distill/llm/llm_client.dart`（全文 76 行）
- Test: `test/distill/llm_tool_message_test.dart`（新建）

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum LlmRole { system, user, assistant, tool }`
  - `class LlmMessage { const LlmMessage(this.role, this.content, {this.toolCalls = const [], this.toolCallId}); final LlmRole role; final String content; final List<LlmToolCall> toolCalls; final String? toolCallId; Map<String, Object?> toJson(); }`
  - `class LlmToolCall { const LlmToolCall({required this.id, required this.name, required this.arguments}); final String id; final String name; final String arguments; }`
  - `class LlmToolSpec { const LlmToolSpec({required this.name, required this.description, required this.parameters}); final String name; final String description; final Map<String, Object?> parameters; Map<String, Object?> toJson(); }`
  - `class LlmTurn { const LlmTurn({this.content = '', this.toolCalls = const []}); final String content; final List<LlmToolCall> toolCalls; bool get wantsTools => toolCalls.isNotEmpty; }`
  - `Future<LlmTurn> LlmClient.completeTurn(List<LlmMessage> messages, {List<LlmToolSpec>? tools, double? temperature, int? maxTokens, CancelToken? cancel})` —— 抽象类里带默认实现。

- [ ] **Step 1: 写失败的测试**

```dart
// test/distill/llm_tool_message_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/llm/llm_client.dart';

class _StubClient implements LlmClient {
  @override
  Stream<String> streamChat(List<LlmMessage> messages,
          {double? temperature, int? maxTokens, CancelToken? cancel}) =>
      const Stream.empty();

  @override
  Future<String> completeJson(List<LlmMessage> messages,
          {double? temperature, int? maxTokens, CancelToken? cancel}) async =>
      '';

  @override
  void dispose() {}
}

void main() {
  test('assistant 带 tool_calls 时输出 OpenAI 形状', () {
    const message = LlmMessage(
      LlmRole.assistant,
      '',
      toolCalls: [
        LlmToolCall(id: 'call_1', name: 'search_in_book', arguments: '{"query":"雨"}'),
      ],
    );
    expect(message.toJson(), {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': 'call_1',
          'type': 'function',
          'function': {'name': 'search_in_book', 'arguments': '{"query":"雨"}'},
        },
      ],
    });
  });

  test('tool 消息带 tool_call_id 且不带 tool_calls', () {
    const message = LlmMessage(LlmRole.tool, '{"hits":[]}', toolCallId: 'call_1');
    expect(message.toJson(), {
      'role': 'tool',
      'content': '{"hits":[]}',
      'tool_call_id': 'call_1',
    });
  });

  test('普通消息不带任何工具字段', () {
    expect(const LlmMessage(LlmRole.user, '你好').toJson(),
        {'role': 'user', 'content': '你好'});
  });

  test('LlmToolSpec 序列化成 function 包装', () {
    const spec = LlmToolSpec(
      name: 'get_chapter',
      description: '读某章',
      parameters: {'type': 'object'},
    );
    expect(spec.toJson(), {
      'type': 'function',
      'function': {
        'name': 'get_chapter',
        'description': '读某章',
        'parameters': {'type': 'object'},
      },
    });
  });

  test('LlmTurn.wantsTools 只在有 toolCalls 时为真', () {
    expect(const LlmTurn(content: '直接回答').wantsTools, isFalse);
    expect(
      const LlmTurn(toolCalls: [LlmToolCall(id: 'a', name: 'b', arguments: '{}')])
          .wantsTools,
      isTrue,
    );
  });

  test('没实现 completeTurn 的客户端明确报错而不是静默成功', () {
    expect(() => _StubClient().completeTurn(const []), throwsUnsupportedError);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/distill/llm_tool_message_test.dart -r compact`
Expected: 编译失败（`LlmRole.tool` / `LlmToolCall` / `LlmToolSpec` / `LlmTurn` 未定义）。

- [ ] **Step 3: 实现模型**

在 `llm_client.dart` 里：`LlmRole` 加 `tool`；`LlmMessage` 增加两个可选具名参数与两个字段（位置构造器不变）；`toJson` 只在 `toolCalls.isNotEmpty` 时输出 `'tool_calls'`、只在 `toolCallId != null` 时输出 `'tool_call_id'`；新增 `LlmToolCall`（带 `toJson()` 输出 `{id, type: 'function', function: {name, arguments}}`）、`LlmToolSpec`、`LlmTurn`；`LlmClient` 末尾加

```dart
  /// One non-streaming turn that may carry tool calls.
  ///
  /// Optional: clients that predate tool calling keep working, they just
  /// cannot be used for the tool loop.
  Future<LlmTurn> completeTurn(
    List<LlmMessage> messages, {
    List<LlmToolSpec>? tools,
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) =>
      throw UnsupportedError('completeTurn 未实现');
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/distill/llm_tool_message_test.dart -r compact`
Expected: 6 个测试全 PASS。

- [ ] **Step 5: 确认没有打破现有假实现**

Run: `flutter analyze && flutter test -r compact`
Expected: 0 issues；608 个测试仍全 PASS。

- [ ] **Step 6: 提交**

```bash
git add lib/distill/llm/llm_client.dart test/distill/llm_tool_message_test.dart
git commit -m "feat(llm): tool messages, tool specs and completeTurn contract"
```

---

### Task 2: HTTP 层发出 tools 请求、解析 tool_calls

**Files:**
- Create: `test/support/fake_llm_server.dart`
- Modify: `test/distill/openai_llm_client_test.dart:1-51`（删除本地 `_FakeLlmServer`，改为 import 共享版）
- Modify: `lib/distill/llm/openai_llm_client.dart:84-211`
- Test: `test/distill/openai_llm_client_turn_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `LlmTurn` / `LlmToolCall` / `LlmToolSpec`。
- Produces: `OpenAiLlmClient.completeTurn(...)`（覆写 Task 1 的契约）；`test/support/fake_llm_server.dart` 导出 `class FakeLlmServer { static Future<FakeLlmServer> start(Future<void> Function(HttpRequest, FakeLlmServer) handler); Uri get baseUrl; final List<String> bodies; Future<void> stop(); }` 与 `Future<void> writeJson(HttpRequest, Map<String, Object?>)`、`Future<void> writeSse(HttpRequest, List<String>)`。

- [ ] **Step 1: 写失败的测试**

```dart
// test/distill/openai_llm_client_turn_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/distill/llm/llm_config.dart';
import 'package:coread/distill/llm/openai_llm_client.dart';
import '../support/fake_llm_server.dart';

void main() {
  const messages = [LlmMessage(LlmRole.user, '雨意味着什么')];
  const tools = [
    LlmToolSpec(
      name: 'search_in_book',
      description: '书内检索',
      parameters: {'type': 'object'},
    ),
  ];

  test('带 tools 的请求体含 tools 与 tool_choice，且 stream 为 false', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_9',
                  'type': 'function',
                  'function': {'name': 'search_in_book', 'arguments': '{"query":"雨"}'},
                },
              ],
            },
          },
        ],
      });
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    final turn = await client.completeTurn(messages, tools: tools);

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    expect(body['stream'], isFalse);
    expect(body['tool_choice'], 'auto');
    expect((body['tools'] as List).single, {
      'type': 'function',
      'function': {
        'name': 'search_in_book',
        'description': '书内检索',
        'parameters': {'type': 'object'},
      },
    });
    expect(turn.content, '');
    expect(turn.toolCalls.single.id, 'call_9');
    expect(turn.toolCalls.single.name, 'search_in_book');
    expect(turn.toolCalls.single.arguments, '{"query":"雨"}');
  });

  test('不带 tools 的请求体里没有 tools 键', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {
        'choices': [
          {'message': {'role': 'assistant', 'content': '直接回答'}},
        ],
      });
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    final turn = await client.completeTurn(messages);

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    expect(body.containsKey('tools'), isFalse);
    expect(body.containsKey('tool_choice'), isFalse);
    expect(turn.content, '直接回答');
    expect(turn.toolCalls, isEmpty);
  });

  test('tool 角色与 tool_calls 原样发到线上', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {
        'choices': [
          {'message': {'role': 'assistant', 'content': '好了'}},
        ],
      });
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    await client.completeTurn([
      const LlmMessage(LlmRole.assistant, '', toolCalls: [
        LlmToolCall(id: 'call_1', name: 'search_in_book', arguments: '{}'),
      ]),
      const LlmMessage(LlmRole.tool, '{"hits":[]}', toolCallId: 'call_1'),
    ]);

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    final sent = body['messages'] as List;
    expect((sent[0] as Map)['tool_calls'], isA<List>());
    expect((sent[1] as Map)['role'], 'tool');
    expect((sent[1] as Map)['tool_call_id'], 'call_1');
  });

  test('响应没有 message 时抛出可读异常', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {'choices': []});
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    expect(client.completeTurn(messages), throwsA(isA<LlmException>()));
  });

  test('400 且正文提到 tools 时保留状态码与正文片段', () async {
    final server = await FakeLlmServer.start((request, _) async {
      request.response.statusCode = 400;
      await writeJson(request, {'error': {'message': 'tools are not supported'}});
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.completeTurn(messages, tools: tools),
      throwsA(isA<LlmException>()
          .having((e) => e.statusCode, 'statusCode', 400)
          .having((e) => e.message, 'message', contains('tools'))),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/distill/openai_llm_client_turn_test.dart -r compact`
Expected: 编译失败（`completeTurn` 未覆写 → 运行时 UnsupportedError；`fake_llm_server.dart` 不存在）。

- [ ] **Step 3: 抽出共享假服务器**

把 `test/distill/openai_llm_client_test.dart:11-51` 的 `_FakeLlmServer` / `_writeJson` / `_writeSse` 搬进 `test/support/fake_llm_server.dart`，改名为公开的 `FakeLlmServer`、`writeJson`、`writeSse`，原测试文件改为 import 并替换引用。跑 `flutter test test/distill/openai_llm_client_test.dart -r compact` 确认 10 个旧测试仍全 PASS 后再继续。

- [ ] **Step 4: 实现 `completeTurn`**

`_writeRequest` 增加一个可选具名参数 `List<LlmToolSpec>? tools`，在 `jsonEncode` 的 map 里按条件补两个键：

```dart
if (tools != null && tools.isNotEmpty) 'tools': tools.map((t) => t.toJson()).toList(),
if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
```

`completeTurn` 复制 `completeJson` 的结构（同一个 `requestTimeout`、同一个 abort 监听、同样的 `_requireConfigured`），差别只有两点：请求体传 `tools`；响应用新的私有静态 `_turnOf(String body)` 解析——`choices[0].message` 缺失或不是 Map 时 `throw LlmException('返回格式异常: ${_snippet(body)}')`；`content` 非 String 时取 `''`；`tool_calls` 里每项取 `id`、`function.name`、`function.arguments`（`arguments` 非 String 时取 `'{}'`），读不出来的项直接跳过。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/distill/openai_llm_client_turn_test.dart -r compact`
Expected: 5 个测试全 PASS。

- [ ] **Step 6: 提交**

```bash
git add lib/distill/llm/openai_llm_client.dart test/distill/openai_llm_client_turn_test.dart test/support/fake_llm_server.dart test/distill/openai_llm_client_test.dart
git commit -m "feat(llm): completeTurn sends tools and parses tool_calls"
```

---

### Task 3: bigram 与两阶段书内检索

**Files:**
- Create: `lib/search/bigrams.dart`
- Modify: `lib/search/book_context.dart:188-199`（`_bigrams` 改为调用共享函数）
- Create: `lib/search/book_searcher.dart`
- Test: `test/search/bigrams_test.dart`、`test/search/book_searcher_test.dart`（新建）

**Interfaces:**
- Consumes: `typedef ChapterLoader` / `typedef ChapterTextLoader`（`lib/search/book_context.dart:6-10`）、`DistillDigestSource`（`lib/distill/distill_digest.dart`，`Future<DistillDigest?> load(String bookId)`、`DistillDigest.gists` 是 `Map<int, String>`）。
- Produces:
  - `Set<String> bigrams(String text)` —— 去标点、转小写、相邻两字符一组。
  - `class BookSnippet { const BookSnippet({required this.chapterIndex, required this.chapterTitle, required this.offset, required this.score, required this.text}); int get chapterNo => chapterIndex + 1; }`
  - `class BookSearch { const BookSearch({required this.hits, required this.truncated}); final List<BookSnippet> hits; final bool truncated; }`
  - `class BookSearcher { BookSearcher({required ChapterLoader loadChapters, required ChapterTextLoader loadChapterText, required DistillDigestSource digests, int maxChapters = 8, int window = 200, int stride = 100, int maxScanChars = 400000}); Future<BookSearch> search(String bookId, String query, {int? chapter, int limit = 3}); }`

> 与 spec §11 的差异：`bigrams` 单独放在 `bigrams.dart` 而不是 `book_searcher.dart`，避免 `book_context.dart` 反向依赖 searcher。

- [ ] **Step 1: 写失败的测试**

```dart
// test/search/book_searcher_test.dart（节选，全部用例见提交）
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/search/book_searcher.dart';

void main() {
  Chapter chapter(int index, String title) => Chapter(
        id: 'c$index',
        bookId: 'b1',
        index: index,
        title: title,
        startOffset: 0,
        endOffset: 100,
        level: 1,
      );

  test('命中按分数降序，每段不超过窗口长度，offset 是窗口起点', () async {
    final texts = {
      0: '雨' * 400,
      1: '风' * 400,
    };
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章'), chapter(1, '第二章')],
      loadChapterText: (_, index) async => texts[index],
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨', limit: 2);

    expect(result.hits, isNotEmpty);
    expect(result.hits.first.chapterIndex, 0);
    expect(result.hits.first.offset % 100, 0);
    expect(result.hits.first.text.length, lessThanOrEqualTo(200));
    final scores = result.hits.map((h) => h.score).toList();
    expect(scores, orderedEquals([...scores]..sort((a, b) => b.compareTo(a))));
  });

  test('chapter 参数只扫那一章（0 基入参）', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章'), chapter(1, '第二章')],
      loadChapterText: (_, index) async => index == 0 ? '雨雨雨' : '雨雨雨',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨', chapter: 1, limit: 3);

    expect(result.hits.every((h) => h.chapterIndex == 1), isTrue);
  });

  test('没有命中时返回空列表而不是抛错', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章')],
      loadChapterText: (_, __) async => '风在吹',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨');

    expect(result.hits, isEmpty);
    expect(result.truncated, isFalse);
  });

  test('未蒸馏时退化为按章序取前 maxChapters 章（不返回空）', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [Chapter(index: 0, ...)],  // 12 章
      loadChapterText: (_, __) async => '雨在夜里落下',
      digests: _NoDigest(),
    );

    final result = await searcher.search('b1', '雨');

    expect(result.hits, isNotEmpty);
  });

  test('超过 maxScanChars 时置 truncated', () async {
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章'), chapter(1, '第二章')],
      loadChapterText: (_, __) async => '雨' * 5000,
      digests: _NoDigest(),
      maxScanChars: 1000,
    );

    final result = await searcher.search('b1', '雨');

    expect(result.truncated, isTrue);
  });

  test('同一章正文在一次检索里只读一次', () async {
    var loads = 0;
    final searcher = BookSearcher(
      loadChapters: (_) async => [chapter(0, '第一章')],
      loadChapterText: (_, __) async {
        loads++;
        return '雨' * 2000;
      },
      digests: _NoDigest(),
    );

    await searcher.search('b1', '雨');
    await searcher.search('b1', '雨');

    expect(loads, 1);
  });
}
```

`_NoDigest` 是同文件里的假 `DistillDigestSource`（`load` 返回 `null`）。`Chapter` 的真实构造器以 `lib/domain/models/chapter.dart` 为准。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/search/bigrams_test.dart test/search/book_searcher_test.dart -r compact`
Expected: 编译失败（`bigrams` / `BookSearcher` 未定义）。

- [ ] **Step 3: 实现 `bigrams.dart` 与 `book_searcher.dart`**

`bigrams` 直接把 `book_context.dart:188-199` 的实现搬过去并公开；`book_context.dart` 的 `_bigrams(...)` 调用处改成 `bigrams(...)`，删掉私有函数。

`search` 的算法（按 spec §11）：

1. 词元 = `bigrams(query)`；为空则直接返回空结果（`truncated: false`）。
2. `chapter != null` → 只处理该章；否则取 `loadChapters(bookId)`，用 `bigrams('${chapter.title}${gists[chapter.index] ?? ''}')` 与词元的交集合打分，取分数 > 0 的前 `maxChapters` 章；**若全部为 0**（未蒸馏时没有 gist），退化为按 `chapter.index` 升序取前 `maxChapters` 章。
3. 逐章 `loadChapterText`，跳过 `null` / 空白；按 `stride` 步长在 `[0, text.length)` 上切长度 `window` 的窗口（最后一段可短于窗口）；累加已扫字符数，超过 `maxScanChars` 就置 `truncated = true` 并停止继续读章。
4. 窗口分数 = `bigrams(windowText) ∩ 词元` 的大小；若窗口文本含完整 `query` 再加 `词元.length`（让整句命中排在散词命中之前）；分数为 0 的窗口丢弃。
5. 全部窗口按分数降序、同分按 `chapterIndex`、再按 `offset` 升序，取前 `limit`。
6. 章正文缓存：`Map<int, String?>` 字段级 LRU，容量 8，按插入顺序淘汰最旧（`remove(head)`）。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/search/bigrams_test.dart test/search/book_searcher_test.dart test/search/book_context_test.dart -r compact`
Expected: 新测试全 PASS，`book_context_test.dart` 的旧断言不变仍 PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/search/bigrams.dart lib/search/book_searcher.dart lib/search/book_context.dart test/search/bigrams_test.dart test/search/book_searcher_test.dart
git commit -m "feat(search): two-stage in-book search over chapter text"
```

---

### Task 4: 工具箱（两个只读工具）

**Files:**
- Create: `lib/search/book_toolbox.dart`
- Test: `test/search/book_toolbox_test.dart`（新建）

**Interfaces:**
- Consumes: `BookSearcher.search`（Task 3）、`BookContext.bookId`、`ChapterTextLoader`。
- Produces:
  - `class BookToolbox { BookToolbox({required BookContext book, required BookSearcher searcher, required ChapterTextLoader loadChapterText}); static const List<LlmToolSpec> specs; Future<String> call(String name, String argumentsJson); }`
  - `static const int maxChapterChars = 3000;`、`static const int maxSnippetChars = 400;`
  - `call` 永不抛异常，返回值一律是可直接塞进 `tool` 消息的 JSON 字符串。

- [ ] **Step 1: 写失败的测试**

```dart
// test/search/book_toolbox_test.dart（节选）
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/search/book_toolbox.dart';

void main() {
  // 用 Task 3 的假 loader 组一个两章的 searcher，bookContext 用 BookContext(...)

  test('search_in_book 返回按章号和偏移标注的命中', () async {
    final raw = await toolbox.call('search_in_book', '{"query":"雨","limit":2}');
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['hits'], isNotEmpty);
    final first = (json['hits'] as List).first as Map;
    expect(first['chapter'], 1);          // 1 基
    expect(first['offset'], isA<int>());
  });

  test('参数不是合法 JSON 时返回 error 而不是抛异常', () async {
    final raw = await toolbox.call('search_in_book', '查询=雨');
    expect(jsonDecode(raw), {'error': '参数不是合法 JSON'});
  });

  test('缺 query 返回 error', () async {
    final raw = await toolbox.call('search_in_book', '{}');
    expect((jsonDecode(raw) as Map)['error'], contains('query'));
  });

  test('limit 被夹到 1..5', () async {
    final raw = await toolbox.call('search_in_book', '{"query":"雨","limit":99}');
    expect((jsonDecode(raw) as List).length, lessThanOrEqualTo(5));
  });

  test('章号越界时返回 error（1 基入参 → 0 基查询）', () async {
    final raw = await toolbox.call('get_chapter', '{"chapter":99}');
    expect((jsonDecode(raw) as Map)['error'], contains('99'));
  });

  test('get_chapter 截到 max_chars 并回带 1 基章号', () async {
    final raw = await toolbox.call('get_chapter', '{"chapter":1,"max_chars":50}');
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['chapter'], 1);
    expect((json['text'] as String).length, lessThanOrEqualTo(51)); // 含省略号
  });

  test('空正文的书返回可读 error', () async {
    final raw = await toolbox.call('get_chapter', '{"chapter":1}');
    expect((jsonDecode(raw) as Map)['error'], contains('正文'));
  });

  test('未知工具名返回 error', () async {
    final raw = await toolbox.call('delete_book', '{}');
    expect((jsonDecode(raw) as Map)['error'], contains('delete_book'));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/search/book_toolbox_test.dart -r compact`
Expected: 编译失败（`BookToolbox` 未定义）。

- [ ] **Step 3: 实现**

`specs` 是两段 `LlmToolSpec`，`name` / `description` / `parameters` 逐字照抄 spec §7 的两段 JSON（`parameters` 用 `Map<String, Object?>` 字面量写）。

`call` 的结构：`jsonDecode`（`FormatException` → `{"error":"参数不是合法 JSON"}`）→ 不是 `Map` 也返回同一个 error → 按 `switch (name)` 分派，未知名字返回 `{"error":"未知工具：$name"}`。

- `search_in_book`：`query` 非空 String 否则 `{"error":"缺少 query"}`；`chapter` 可空 int；`limit` 默认 3、`clamp(1, 5)`；`chapter` 给了就 `chapter - 1` 传给 `searcher.search`，返回体 `{"query": query, "chapter": chapter, "truncated": bool, "hits": [{"chapter": chapterNo, "title": ..., "offset": ..., "score": ..., "text": 截到 400 字}]}`。
- `get_chapter`：`chapter` 必须是 int 否则 `{"error":"缺少 chapter"}`；越界（`< 1` 或 `> 章数`）→ `{"error":"第 N 章不存在"}`。章数从 `searcher` 拿不到，所以 `BookToolbox` 额外持有 `int chapterCount`（构造参数）。正文 `null` 或 `trim().isEmpty` → `{"error":"第 N 章没有正文"}`；`offset` 从 0 起、超过正文长度时按末尾处理；`max_chars` 默认 2000、`clamp(1, 3000)`；`text` 超长时用 `_clip` 截断并补 `…`（复用与 `book_context.dart:185` 相同的写法）。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/search/book_toolbox_test.dart -r compact`
Expected: 8 个测试全 PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/search/book_toolbox.dart test/search/book_toolbox_test.dart
git commit -m "feat(search): read-only book toolbox for search_in_book and get_chapter"
```

---

### Task 5: ReAct 循环

**Files:**
- Create: `lib/search/search_step.dart`、`lib/search/tool_agent.dart`
- Test: `test/search/search_step_test.dart`、`test/search/tool_agent_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 `LlmTurn` / `LlmToolSpec` / `LlmToolCall`、Task 4 `BookToolbox.call` 与 `specs`、`SearchAgentService.buildMessages`（复用它拼 system prompt 的 book/memory/hits 部分）、`BookMemory.promptBlock()`。
- Produces:
  - `class SearchStep { const SearchStep({required this.tool, required this.summary, required this.chapters, required this.hits, required this.ms}); final String tool; final String summary; final List<int> chapters; final int hits; final int ms; Map<String, Object?> toJson(); static String listToJson(List<SearchStep> steps); static List<SearchStep> listFromJson(String? json); }`（`listFromJson` 遇到坏 JSON 返回空列表，不抛）
  - `typedef TextSink = void Function(String delta);`、`typedef StepSink = void Function(SearchStep step);`
  - `class ToolRunResult { const ToolRunResult({required this.steps, required this.toolCalls}); final List<SearchStep> steps; final int toolCalls; }`
  - `class ToolUnsupportedException implements Exception { const ToolUnsupportedException(this.cause); final Object cause; }`
  - `class SearchToolAgent { SearchToolAgent({required LlmClient client, int maxSteps = 4, int maxToolChars = 6000, int decisionMaxTokens = 500, Duration deadline = const Duration(seconds: 90), DateTime Function()? now, double temperature = 0.7, int? maxTokens = 2000}); Future<ToolRunResult> run({required List<LlmMessage> history, required String userText, required BookContext book, required BookToolbox toolbox, BookMemory? memory, List<SearchHit> hits = const [], required CancelToken cancel, required TextSink onText, required StepSink onStep}); }`

> `BookToolbox` 由调用方按书构造后传入 `run`，不进 agent 的构造器——这样 agent 本身无状态，一个 provider 全局够用。

- [ ] **Step 1: 写失败的测试**

```dart
// test/search/tool_agent_test.dart（节选）
class _ScriptedClient implements LlmClient {
  _ScriptedClient(this.turns);
  final List<LlmTurn> turns;                 // completeTurn 依次消费
  final List<List<LlmMessage>> seen = [];    // 每次请求的 messages
  final List<List<LlmToolSpec>?> toolsSent = [];
  String answer = '最终答案';
  int _i = 0;

  @override
  Future<LlmTurn> completeTurn(List<LlmMessage> messages,
      {List<LlmToolSpec>? tools, double? temperature, int? maxTokens,
       CancelToken? cancel}) async {
    seen.add(List.of(messages));
    toolsSent.add(tools);
    return turns[_i++];
  }

  @override
  Stream<String> streamChat(List<LlmMessage> messages,
      {double? temperature, int? maxTokens, CancelToken? cancel}) async* {
    seen.add(List.of(messages));
    yield answer;
  }

  @override
  Future<String> completeJson(List<LlmMessage> messages,
      {double? temperature, int? maxTokens, CancelToken? cancel}) async => '';
  @override
  void dispose() {}
}

void main() {
  test('一轮检索后流式给出答案，tool 消息紧跟 assistant tool_calls', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [
        LlmToolCall(id: 'call_1', name: 'search_in_book', arguments: '{"query":"雨"}'),
      ]),
      const LlmTurn(content: ''),
    ]);
    final steps = <SearchStep>[];
    final text = <String>[];

    await agent(client).run(... onText: text.add, onStep: steps.add);

    final second = client.seen[1].map((m) => m.role).toList();
    expect(second.contains(LlmRole.tool), isTrue);
    expect(client.seen[1].lastWhere((m) => m.role == LlmRole.tool).toolCallId, 'call_1');
    expect(steps.single.chapters, isNotEmpty);
    expect(text.join(), '最终答案');
  });

  test('一个响应带两个 tool_calls → 两个 step、两条 tool 消息', () async {
    // turns[0] 含 call_1 / call_2；断言 seen[1] 里 tool 消息恰好 2 条且 id 顺序一致
  });

  test('达到 4 步上限后发不带 tools 的收尾请求', () async {
    // 连续 5 个含 tool_calls 的 turn；断言 toolsSent.last == null，
    // 且 seen.last 的末尾 system/user 提醒含「上限」
  });

  test('相同参数第二次调用不再执行，改为补一条 error 的 tool 消息', () async {
    // 两次一模一样的 arguments；断言只有 1 个 step，且第 2 条 tool 内容含 "skipped"
  });

  test('工具抛出异常时回 error 的 tool 消息而不是整轮失败', () async {
    // toolbox.call 抛 StateError；断言 run 正常返回
  });

  test('工具输出累计超过 maxToolChars 后停止喂更多结果', () async {
    // maxToolChars: 100 时，第 2 次检索的 tool 内容为 {"error":"skipped: ...
  });

  test('cancel 在工具执行前被调用则不再发请求', () async {
    // run 里在 onStep 回调中 cancel.cancel()；断言 seen.length == 1
  });

  test('超过 deadline 立即走收尾请求（不带 tools）', () async {
    // now 依次返回 0s、91s；断言 toolsSent.last == null
  });

  test('首轮就没有 tool_calls 时不产生任何 step，直接流式', () async {
    // turns 只有一条 content；断言 steps 为空、toolsSent.single != null
  });

  test('400 且正文提到 tools 时抛 ToolUnsupportedException', () async {
    // completeTurn 抛 LlmException('HTTP 400: ... tools ...', statusCode: 400)
  });
}
```

（节选只给第一个用例的完整断言；其余用例按注释里的断言写，同样先失败。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/search/tool_agent_test.dart test/search/search_step_test.dart -r compact`
Expected: 编译失败（`SearchToolAgent` / `SearchStep` 未定义）。

- [ ] **Step 3: 实现 `search_step.dart`**

`toJson` → `{'tool': tool, 'summary': summary, 'chapters': chapters, 'hits': hits, 'ms': ms}`；`listToJson` → `jsonEncode(steps.map((s) => s.toJson()).toList())`；`listFromJson` → `null`/空白返回 `const []`，`jsonDecode` 抛 `FormatException` 时返回 `const []`，元素不是 Map 的跳过。

- [ ] **Step 4: 实现 `tool_agent.dart`**

一次 `run` 的执行顺序（严格按 spec §8.1）：

1. `if (cancel.isCanceled) return const ToolRunResult(steps: [], toolCalls: 0);`
2. `deadlineAt = now() + deadline`；`messages = _buildMessages(...)` —— 复用 `SearchAgentService.buildMessages(history:, userText:, hits:, book:, memory:)` 的结果，但在末尾追加一段工具规则（常量 `searchToolRules`，写清「先看蒸馏定位章节 → 需要原文证据时调 search_in_book → 引用写成 `>` 块并标（第 N 章）→ 找不到就说没有写到」），**不要自己重写 book/memory 的拼接**。
3. 循环：`if (now().isAfter(deadlineAt)) break;` → `turn = await client.completeTurn(messages, tools: BookToolbox.specs, temperature:, maxTokens: decisionMaxTokens, cancel:)`。`LlmException` 且 `statusCode != null && statusCode >= 400` 且 `message.contains('tool') || message.contains('function')` → `throw ToolUnsupportedException(error)`。
4. `turn.wantsTools == false` → 记下 `turn.content` 作为答案前缀（非空时先 `onText` 一次），`break`。
5. 否则：`assistantMessage = LlmMessage(LlmRole.assistant, turn.content, toolCalls: turn.toolCalls)` 追加；对每个 call 依次决定「执行 / 跳过」，并把**每个** call 的 tool 消息追加（`LlmMessage(LlmRole.tool, payload, toolCallId: call.id)`）。跳过条件（按顺序判断）：步数已满 → `{"error":"skipped: step_limit"}`；参数与之前完全相同 → `{"error":"skipped: duplicate"}`；预算已满 → `{"error":"skipped: budget"}`。执行成功时 `payload = await toolbox.call(call.name, call.arguments)`，累加 `budget += payload.length`，并 `onStep` 一个 `SearchStep`（`summary` 形如 `检索「雨」` 或 `读第 7 章`，`chapters` 从返回 JSON 的 `hits`/`chapter` 取 1 基章号，`ms` 用 `now()` 差算整毫秒）。
6. 回到 3。
7. 收尾：`messages` 追加一条 `LlmMessage(LlmRole.user, '已达到检索上限，请基于已有材料作答。')`（步数满时才加；deadline 中断则用「已耗时过长，请基于已有材料作答。」），然后 `await for (final delta in client.streamChat(messages, temperature:, maxTokens:, cancel:))` 逐段 `onText(delta)`。
8. 返回 `ToolRunResult(steps: steps, toolCalls: executedCalls)`。

**协议硬规则**：第 5 步里只要追加了带 `tool_calls` 的 assistant 消息，就必须在同一个分支里为它的每个 `call.id` 追加一条 tool 消息，包括跳过的情况；顺序与 `turn.toolCalls` 一致。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/search/tool_agent_test.dart test/search/search_step_test.dart -r compact`
Expected: 两个文件的全部用例 PASS。

- [ ] **Step 6: 提交**

```bash
git add lib/search/tool_agent.dart lib/search/search_step.dart test/search/tool_agent_test.dart test/search/search_step_test.dart
git commit -m "feat(search): ReAct tool loop with step, budget and deadline limits"
```

---

### Task 6: 书上下文的工具路径形态

**Files:**
- Modify: `lib/search/book_context.dart:78-145`
- Test: `test/search/book_context_test.dart`（补充用例）

**Interfaces:**
- Consumes: 现有 `BookContextBuilder`。
- Produces: `Future<BookContext?> BookContextBuilder.build(String bookId, {String question = '', bool includeExcerpts = true, int? briefChars})` —— 新增两个可选参数，默认行为与今天完全一致。

- [ ] **Step 1: 写失败的测试**

```dart
test('includeExcerpts: false 时不带原文片段', () async {
  final context = await builder.build('b1', question: '雨', includeExcerpts: false);
  expect(context!.excerpts, isEmpty);
  expect(context.distilled, isTrue);
});

test('briefChars 覆盖默认 brief 预算', () async {
  final context = await builder.build('b1', briefChars: 3600);
  expect(context!.brief.length, greaterThan(2400));
});

test('超过 40 章只给标题，并如实标注总数', () async {
  final context = await builder.build('b1', briefChars: 3600);
  expect(context!.brief, contains('第 41 章'));
  expect(context.brief, contains('共 45 章'));
  expect(context.brief, isNot(contains('第 41 章 第一章' + '：')));  // 41 章往后没有 gist
});

test('章节远超上限时标注「此处只列」', () async {
  final context = await builder.build('big', briefChars: 3600);
  expect(context!.brief, contains('此处只列'));
});
```

（构造 45 章 / 300 章两套假 loader；gist 用 `Map<int, String>` 的假 `DistillDigestSource`。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/search/book_context_test.dart -r compact`
Expected: 编译失败（`includeExcerpts` / `briefChars` 不存在）。

- [ ] **Step 3: 实现**

- `build` 签名加两个可选参数；`briefChars ?? maxBriefChars` 传给 `_brief`；`includeExcerpts == false` 时 `excerpts` 直接取 `const <BookExcerpt>[]`（连 `_excerpts` 都不调用）。
- `_brief` 接收 `maxChars`：目录部分改成两段——前 `maxGists` 章带 gist（现状），其后最多 200 章只写 `第 N 章 标题`，前缀一行「其余章节（仅标题）：」；若仍被截断（`chapters.length > maxGists + 200`）在目录末尾写「（共 N 章，此处只列 M 章）」，否则写「（共 N 章）」。`M` 是实际写出的章数。
- 仍以 `_clip(buffer.toString(), maxChars)` 收尾；`briefChars: 3600` 时标题-only 段能装下约 200 行。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/search/book_context_test.dart -r compact`
Expected: 新老用例全 PASS（默认参数下旧断言不变）。

- [ ] **Step 5: 提交**

```bash
git add lib/search/book_context.dart test/search/book_context_test.dart
git commit -m "feat(search): tool-path context drops excerpts and widens the chapter map"
```

---

### Task 7: stepsJson 落库（迁移 12 → 13）

**Files:**
- Modify: `lib/data/db/tables.dart:171-184`
- Modify: `lib/data/db/app_database.dart:34`、`:142`（在 `if (from < 12)` 之后追加分支）
- Modify: `lib/data/repositories/chat_repository.dart:139-185`
- Regenerate: `lib/data/db/app_database.g.dart`（工具生成，不手改）
- Test: `test/data/migration_test.dart`、`test/data/chat_repository_test.dart`（各补用例）

**Interfaces:**
- Consumes: Task 5 的 `SearchStep.listToJson` / `listFromJson` 只是消费者，本任务不依赖它。
- Produces: `ChatMessages.stepsJson` 列；`ChatMessageRepository.append({..., String? stepsJson})`；`Future<void> updateSteps(String id, String? stepsJson)`。

- [ ] **Step 1: 写失败的测试**

```dart
// migration_test.dart 追加
test('upgrades a v12 database and keeps old rows readable', () async {
  final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
    raw.execute('PRAGMA user_version = 12;');
    raw.execute(
      'CREATE TABLE chat_messages ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'thread_id TEXT NOT NULL, '
      "role TEXT NOT NULL, "
      "content TEXT NOT NULL, "
      'sources_json TEXT, '
      "status TEXT NOT NULL DEFAULT 'complete', "
      'created_at TEXT NOT NULL)',
    );
    raw.execute(
      "INSERT INTO chat_messages VALUES "
      "('m1','t1','assistant','旧回答',NULL,'complete','2026-01-01T00:00:00.000Z')",
    );
  }));

  final columns = await db
      .customSelect('PRAGMA table_info(chat_messages)')
      .get();
  expect(columns.map((r) => r.read<String>('name')), contains('steps_json'));
  final row = await (db.select(db.chatMessages)).getSingle();
  expect(row.stepsJson, isNull);
  expect(row.content, '旧回答');
});
```

```dart
// chat_repository_test.dart 追加
test('updateSteps 写入后能读回，传 null 会清空', () async {
  final message = await repo.append(threadId: 't1', role: 'assistant', content: '答案');
  await repo.updateSteps(message.id, '[{"tool":"search_in_book"}]');
  var rows = await repo.list('t1');
  expect(rows.single.stepsJson, '[{"tool":"search_in_book"}]');
  await repo.updateSteps(message.id, null);
  rows = await repo.list('t1');
  expect(rows.single.stepsJson, isNull);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/migration_test.dart test/data/chat_repository_test.dart -r compact`
Expected: 编译失败（`stepsJson` / `updateSteps` 未定义）。

- [ ] **Step 3: 改表与迁移**

`tables.dart` 的 `ChatMessages` 在 `sourcesJson` 之后加 `TextColumn get stepsJson => text().nullable()();`。
`app_database.dart`：`schemaVersion` 改 13；在 `if (from < 12) {...}` 之后追加——

```dart
          if (from < 13) {
            // The v11 block creates chat_messages from the current definition,
            // so a table upgraded through it already has the column.
            final columns = await m.database
                .customSelect('PRAGMA table_info(chat_messages)')
                .get();
            final hasSteps =
                columns.any((row) => row.read<String>('name') == 'steps_json');
            if (!hasSteps) {
              await m.addColumn(chatMessages, chatMessages.stepsJson);
            }
          }
```

然后 `dart run build_runner build --delete-conflicting-outputs` 重新生成 `app_database.g.dart`。

- [ ] **Step 4: 加仓储方法**

`append` 增加可选 `String? stepsJson`（`ChatMessagesCompanion.insert` 里 `stepsJson: Value(stepsJson)`）；新增：

```dart
  Future<void> updateSteps(String id, String? stepsJson) {
    return (_db.update(_db.chatMessages)..where((row) => row.id.equals(id)))
        .write(ChatMessagesCompanion(stepsJson: Value(stepsJson)));
  }
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/data/migration_test.dart test/data/chat_repository_test.dart -r compact`
Expected: 新旧用例全 PASS（含原来的 v5→v12 用例）。

- [ ] **Step 6: 提交**

```bash
git add lib/data/db/tables.dart lib/data/db/app_database.dart lib/data/db/app_database.g.dart lib/data/repositories/chat_repository.dart test/data/migration_test.dart test/data/chat_repository_test.dart
git commit -m "feat(db): persist tool steps on chat messages (schema 13)"
```

---

### Task 8: 接线——搜壳走工具路径

**Files:**
- Modify: `lib/search/search_config.dart`（加两个 key 与读取辅助）
- Modify: `lib/app/providers.dart:465-479`（新增 `bookSearcherProvider`、`bookToolboxProvider(bookId)`、`searchToolAgentProvider`）
- Modify: `lib/features/search/chat_controller.dart:294-395`
- Test: `test/features/search_shell_test.dart`（补充用例）

**Interfaces:**
- Consumes: Task 5 `SearchToolAgent.run`、Task 6 `build(includeExcerpts: false, briefChars: 3600)`、Task 7 `updateSteps`、`SettingsRepository.get/set`、`LlmConfig.modelKey`。
- Produces: `SearchConfig.toolsEnabledKey = 'search.toolsEnabled'`、`static String toolsUnsupportedKey(String model) => 'search.toolsUnsupported.$model';`；`SearchConfigStore.toolsEnabled()` / `setToolsEnabled(bool)` / `isToolsUnsupported(String model)` / `markToolsUnsupported(String model)`。

- [ ] **Step 1: 写失败的测试**

```dart
// search_shell_test.dart 追加（沿用该文件现有的容器/假服务搭建方式）
test('绑书且开着工具时走工具路径，步骤写进 stepsJson', () async {
  // 假 SearchToolAgent：onStep 两次、onText 输出「答案」
  // 断言：终态 assistant 行 content == '答案'、stepsJson 含两个 tool 名、
  //       且 bookContextBuilder 收到 includeExcerpts: false
});

test('端点报告不支持工具时降级并写入 notice 与 toolsUnsupported', () async {
  // 假 agent 抛 ToolUnsupportedException
  // 断言：content 来自降级 agent、stepsJson 含 'notice'、
  //       settings['search.toolsUnsupported.<model>'] == 'true'、status == 'complete'
});

test('没有章节正文的书不进工具路径', () async {
  // loadChapterText 全返回 null；断言 toolsAgent 未被调用、旧 agent 被调用
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/search_shell_test.dart -r compact`
Expected: 新用例失败（工具路径不存在，仍走旧 agent）。

- [ ] **Step 3: 加设置读写**

`SearchConfig` 里加两个常量与 `SearchConfigStore` 的四个方法（`toolsEnabled` 缺省为 `true`，只有显式 `'false'` 才是关）。`markToolsUnsupported` 写 `'true'`。

- [ ] **Step 4: 加 providers**

```dart
final bookSearcherProvider = Provider<BookSearcher>((ref) => BookSearcher(
      loadChapters: (id) => ref.read(chapterRepositoryProvider).getSummariesForBook(id),
      loadChapterText: (id, index) => ref.read(chapterRepositoryProvider).getContent(id, index),
      digests: ref.read(distillDigestSourceProvider),
    ));

final bookToolboxProvider = Provider.family<BookToolbox, String>((ref, bookId) => ...);
final searchToolAgentProvider = Provider<SearchToolAgent>(
  (ref) => SearchToolAgent(client: ref.watch(llmClientProvider)),
);
```

`BookToolbox` 需要 `BookContext`、`chapterCount`、`searcher`、`loadChapterText`，所以它不能是 `Provider`——在 `_stream` 里就地构造：`BookToolbox(book: bookContext, chapterCount: chapters.length, searcher: ref.read(bookSearcherProvider), loadChapterText: ...)`，然后作为 `run(toolbox: ...)` 的参数传进去（Task 5 的签名就是这么定的）。

- [ ] **Step 5: 改 `_stream`**

在**现有 `bookContextBuilderProvider.build` 调用之前**插入判定：

```
useTools = bookId != null
        && await store.toolsEnabled()
        && !await store.isToolsUnsupported(currentModel)
        && bookId 有正文（chapterRepository.getContent(bookId, 0) 非 null 且非空白）
```

- `useTools` 为真：`bookContext = await builder.build(bookId, includeExcerpts: false, briefChars: 3600)`；取 `chapters = await chapterRepository.getSummariesForBook(bookId)`；构造 toolbox 与 agent；`await for`-等价地调用：

```dart
final result = await toolAgent.run(
  history: history,
  userText: userText,
  book: bookContext,
  memory: memory,
  hits: hits,
  cancel: cancel,
  onText: (delta) {
    if (cancel.isCanceled || _disposed) return;
    buffer.write(delta);
    _patchAssistant(assistantId, buffer.toString());
  },
  onStep: (step) async { ... }  // 见下
);
```

`onStep` 同步回调里不能 await 仓储；改成把 step 收进 `final steps = <SearchStep>[]` 并由一个 `_persistSteps()` 在每次 step 后调用（`messageRepo.updateSteps(assistantId, SearchStep.listToJson(steps))`，不 await 结果、忽略异常）。节流 `flush('streaming')` 逻辑保持不动。
- 捕获 `ToolUnsupportedException`：`await store.markToolsUnsupported(model)`；`steps.add` 一条 notice（写成 `SearchStep(tool: 'notice', summary: '当前模型不支持工具检索，已用摘要回答', chapters: const [], hits: 0, ms: 0)`），落库；然后重跑一次**经典路径**（`bookContext` 用 `question: userText` 重新 build，`agentServiceProvider.send(...)`），文本继续写进同一个 `buffer`。
- 其他异常：保持现有 `failed` 处理。
- `useTools` 为假：维持现有代码路径，一行不改。

无论哪条路径，退出 `_stream` 前都用 `SearchStep.listToJson(steps)`（空则 `null`）写一次 `stepsJson`，与 `updateContent` 一起落库。

- [ ] **Step 6: 跑测试确认通过**

Run: `flutter test test/features/search_shell_test.dart -r compact`，然后 `flutter test -r compact`
Expected: 新用例 PASS，其余全绿。

- [ ] **Step 7: 提交**

```bash
git add lib/search/search_config.dart lib/app/providers.dart lib/features/search/chat_controller.dart test/features/search_shell_test.dart
git commit -m "feat(search): route book-bound questions through the tool loop"
```

---

### Task 9: 步骤行与设置开关

**Files:**
- Create: `lib/features/search/steps_bar.dart`
- Modify: `lib/features/search/message_list.dart:42-46`、`:111-143`
- Modify: `lib/features/settings/settings_page.dart`（LLM 分组下方加一行开关）
- Test: `test/features/steps_bar_test.dart`、`test/features/message_list_steps_test.dart`、`test/features/settings_page_test.dart`（补用例）

**Interfaces:**
- Consumes: `SearchStep.listFromJson`（Task 5）、`SearchConfig.toolsEnabledKey`（Task 8）。
- Produces: `class StepsBar extends StatelessWidget { const StepsBar({super.key, required this.steps, required this.streaming}); }`；`_AssistantBlock` 在 `MarkdownMessage` **上方**渲染它。

- [ ] **Step 1: 写失败的测试**

```dart
// steps_bar_test.dart
testWidgets('折叠态显示次数与章号，展开后列出每一步', (tester) async {
  final steps = [
    const SearchStep(tool: 'search_in_book', summary: '检索「雨」', chapters: [3, 7], hits: 2, ms: 120),
    const SearchStep(tool: 'get_chapter', summary: '读第 12 章', chapters: [12], hits: 1, ms: 80),
  ];
  await tester.pumpWidget(_host(StepsBar(steps: steps, streaming: false)));

  expect(find.textContaining('检索 2 次'), findsOneWidget);
  expect(find.textContaining('第 3、7、12 章'), findsOneWidget);

  await tester.tap(find.byKey(const Key('steps-bar-toggle')));
  await tester.pumpAndSettle();
  expect(find.textContaining('检索「雨」'), findsOneWidget);
  expect(find.textContaining('读第 12 章'), findsOneWidget);
});

testWidgets('运行中显示最后一步并带进度圈', (tester) async {
  await tester.pumpWidget(_host(StepsBar(steps: [/* 一条 */], streaming: true)));
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  expect(find.textContaining('检索'), findsWidgets);
});

testWidgets('notice 条目渲染成灰字提示', (tester) async {
  await tester.pumpWidget(_host(StepsBar(steps: [noticeStep], streaming: false)));
  expect(find.textContaining('不支持工具检索'), findsOneWidget);
});
```

```dart
// message_list_steps_test.dart
testWidgets('带 stepsJson 的助手行在正文上方渲染步骤条', (tester) async {
  // ChatMessageRow(content: '答案', stepsJson: '[{...}]')
  expect(find.byType(StepsBar), findsOneWidget);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/steps_bar_test.dart test/features/message_list_steps_test.dart -r compact`
Expected: 编译失败（`StepsBar` 未定义）。

- [ ] **Step 3: 实现 StepsBar**

- `streaming == false`：`InkWell(key: Key('steps-bar-toggle'))` 一行 —— 图标 `Icons.travel_explore`，文案「检索 N 次 · 第 A、B、C 章」（章号去重升序，超过 6 个写 `…`；`chapters` 全空时只写「检索 N 次」）；展开后每步一行 `summary` + 右侧 `$ms ms`。
- `streaming == true`：`CircularProgressIndicator(strokeWidth: 2)` + 最后一步的 `summary`（`steps` 为空时「正在判断要不要翻书…」），不可展开。
- notice 条目（`tool == 'notice'`）：灰色圆角条 + `Icons.info_outline` + `summary`，不参与「检索 N 次」计数。

- [ ] **Step 4: 接进气泡与设置页**

`message_list.dart`：`_AssistantBlock` 用 `SearchStep.listFromJson(row.stepsJson)` 取步骤，非空时在 `MarkdownMessage` 之上渲染 `StepsBar(steps: steps, streaming: row.status == 'streaming')`——注意 `MessageList` 现在 `else if (row.content.isNotEmpty)` 才渲染助手行，改成「有内容**或有步骤**就渲染」，否则第一个 token 到达前看不见「翻到第 7 章…」。

`settings_page.dart`：在 LLM 分组下加 `SwitchListTile`，`key: const Key('settings-tools-switch')`，标题「书内检索工具」，副标题「多一次请求，让模型自己在选中的书里翻找原文」，值读 `searchConfigStoreProvider.toolsEnabled()`，切换时 `setToolsEnabled(value)` 并 `ref.invalidate(searchConfigProvider)`。若 `isToolsUnsupported(<当前模型>)` 为真，副标题追加「（当前模型报告不支持，已暂停）」。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/features/steps_bar_test.dart test/features/message_list_steps_test.dart test/features/settings_page_test.dart -r compact`
Expected: 全 PASS。

- [ ] **Step 6: 提交**

```bash
git add lib/features/search/steps_bar.dart lib/features/search/message_list.dart lib/features/settings/settings_page.dart test/features/steps_bar_test.dart test/features/message_list_steps_test.dart test/features/settings_page_test.dart
git commit -m "feat(search): visible tool steps and the tools switch"
```

---

### Task 10: 验收、README 与全量回归

**Files:**
- Modify: `README.md`（仓库根，131 行）
- Test: 无新测试；跑全量

- [ ] **Step 1: 全量回归**

Run: `flutter analyze && flutter test -r compact`
Expected: `0 issues`；所有测试 PASS（608 + 新增）。

- [ ] **Step 2: 手工验收（照 spec §12）**

用一本已蒸馏的书，在设置里确认开关为开：

1. 问「这本书里反复出现的雨意味着什么」→ 回答上方出现步骤行，章号不是问题里出现过的词也能命中。
2. 关掉开关问同一句 → 没有步骤行，只有摘要级回答。两步对比记下，作为 README 的证据。
3. 问「第三章那个老人说了什么」→ 步骤行为 `get_chapter`，不搜全书。
4. 打开一本 PDF 或漫画书提问 → 不进工具路径，行为与今天一致。
5. 提问中途点「停止」→ 立刻停，已出内容与已完成的步骤行都在。
6. 切走再切回来 / 重启应用 → 步骤行仍在。

- [ ] **Step 3: 更新 README**

在「AI 接入 / 搜」那一节追加一小段：书内检索工具是什么、两个工具的名字、开关在哪、端点不支持时的降级行为，以及上面第 1/2 步的前后对比结论（一句话 + 各自观察到的差异）。

- [ ] **Step 4: 提交**

```bash
git add README.md
git commit -m "docs: describe the in-book tool loop and how to compare it"
```
