# 搜/阅 分叉入口 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 冷启动先选「搜」或「阅」；「阅」= 现有书架，保持原样；「搜」= 落库的通用 agent 对话页（流式、可停止、可联网检索），左上角可互切。

**Architecture:** `BookApp.home` 换成 `RootView`：`modeProvider` 为 `null` 显示 `LauncherPage`，选定后用懒构建的 `IndexedStack` 同时保活两个壳（阅=`AppShell`，搜=`SearchShell`）。「搜」的对话状态放在会话级 controller（keepAlive），流式回答按节流写进 Drift（`ChatMessages.status` 区分 streaming/complete/interrupted），因此切页、切会话、关窗都不丢半截内容。

**Tech Stack:** Flutter 3.47.9 / Dart 3.13.7、Riverpod 3、Drift 2、`dart:io HttpClient`（复用 `OpenAiLlmClient` / `CancelToken`）、`flutter_markdown`（新增）。

**Spec:** `docs/superpowers/specs/2026-11-04-search-and-read-shell-design.md`

## Global Constraints

- 数据库迁移：`schemaVersion` 6 → 7，必须走 `onUpgrade` 的 `if (from < 7)`，不改老表、不加外键。
- 「阅」的既有行为不得退化：书架、分类、导入、删除、阅读页、蒸馏、陪读、设置全部照旧。
- 不新增 HTTP 包（用 `dart:io`）；新增依赖只有 Markdown 渲染包。
- 平台：Windows 桌面 + Android；窄屏（< 900dp）侧栏走 Drawer。
- 每个任务结束时 `flutter analyze` 干净、相关测试通过；全量测试保持全绿。
- 文案中文。测试里的 Key 命名沿用 `rail-bookshelf` 这类风格。

## Review Focus

- **入口页每次冷启动都出现**（不记住上次）：从桌面/安卓杀进程重进，必须先看到两张卡，而不是直接落到上次的壳。
- **流式中途切走再回来**：切到「阅」再切回「搜」，已出的字不能丢、不能重发请求。
- **关窗 / 被杀时正在流式**：重启后那条回答显示半截 + 「已中断」，不显示成完整回答，也不能永久停在"正在回答"。
- **未配置模型 / 未配置搜索**：点发送不能崩，要给出「去设置」；「联网」开着但没配 key 时不能静默当没联网。
- **检索失败或 0 结果**：这一轮降级为不联网继续回答 + 灰色提示，而不是整轮报错。
- **窄屏**：窗口缩到手机宽度时，侧栏收进 Drawer，消息与输入框仍可用，不出现横向溢出。

---

### Task 1: 根视图与入口页

**Files:**
- Create: `lib/features/root/app_mode.dart`, `lib/features/root/root_view.dart`, `lib/features/root/launcher_page.dart`
- Modify: `lib/app/app.dart:15`, `lib/features/home/app_shell.dart:19`（后面 Task 2 再加开关）
- Test: `test/features/launcher_page_test.dart`, `test/app/app_shell_test.dart:26-45`

**Interfaces:**
- Produces: `enum AppMode { read, search }`；`final modeProvider = NotifierProvider<AppModeNotifier, AppMode?>`，`AppModeNotifier.select(AppMode)` / `.reset()`；`RootView`（无参 ConsumerWidget）；`LauncherPage({required ValueChanged<AppMode> onPick})`。

- [ ] **Step 1: 写失败测试**（`test/features/launcher_page_test.dart`）

```dart
testWidgets('冷启动显示入口页，点「阅」进书架', (tester) async {
  await pumpApp(tester);                       // ProviderScope + BookApp，见文件内 helper
  expect(find.text('今天想做什么？'), findsOneWidget);
  expect(find.byKey(const Key('launcher-search')), findsOneWidget);
  await tester.tap(find.byKey(const Key('launcher-read')));
  await tester.pumpAndSettle();
  expect(find.text('今天想做什么？'), findsNothing);
  expect(find.byTooltip('书架'), findsOneWidget);
});
```

- [ ] **Step 2: 跑测试确认失败**：`flutter test test/features/launcher_page_test.dart` → 找不到 `今天想做什么？`。

- [ ] **Step 3: 实现**

`app_mode.dart`：`enum AppMode { read, search }` + `AppModeNotifier extends Notifier<AppMode?>`（`build() => null`，`select(m) => state = m`，`reset() => state = null`）+ `modeProvider`。

`launcher_page.dart`：`Scaffold` + 居中 `Column`：标题文本 `今天想做什么？`，两张 `Card`（`Key('launcher-search')` / `Key('launcher-read')`，大图标 + 「搜」/「阅」+ 一行说明），`LayoutBuilder` 宽度 ≥ 720 时 `Row` 并排，否则 `Column`。

`root_view.dart`：`ConsumerWidget`，`mode == null` → `LauncherPage(onPick: ref.read(modeProvider.notifier).select)`；否则维护 `Set<AppMode> _built`（放在 `ConsumerStatefulWidget` 里），`IndexedStack(index: mode.index, children: [for each mode: _built.contains(m) ? shell : const SizedBox.shrink()])`，`initState`/`didChangeDependencies` 里把当前 mode 加入 `_built`。搜壳先用 `Scaffold(body: Center(child: Text('搜')))` 占位。

`app.dart:15` → `home: const RootView()`。

- [ ] **Step 4: 跑测试通过**；同时更新 `test/app/app_shell_test.dart`：先 pump，再 `tap(Key('launcher-read'))`，`pumpAndSettle`，再断言书架。

- [ ] **Step 5: 提交**：`git add lib/app lib/features/root test/features/launcher_page_test.dart test/app/app_shell_test.dart && git commit -m "feat(root): add launcher with read/search modes"`

### Task 2: 左上角模式开关

**Files:**
- Create: `lib/features/root/mode_switch.dart`
- Modify: `lib/features/home/section_rail.dart:29-88`（加 `leading` 插槽，替换写死的「阅」方块）、`lib/features/home/app_shell.dart:19`、`lib/features/root/root_view.dart`（搜壳顶栏放横向开关）
- Test: `test/features/mode_switch_test.dart`

**Interfaces:**
- Produces: `ModeSwitch({required AppMode mode, required ValueChanged<AppMode> onChanged, Axis axis = Axis.vertical})`；`SectionRail` 新增可选 `Widget? leading`（Null 时保留原「阅」方块）。

- [ ] **Step 1: 写失败测试**：点 `Key('mode-switch-search')` 后 `find.text('今天想做什么？')` 不存在、搜壳可见；再点 `Key('mode-switch-read')` 回到书架；且切走再切回时搜壳的 `TextField` 内容仍在（`expect(find.text('草稿'), findsOneWidget)`）。

- [ ] **Step 2: 跑测试确认失败**。

- [ ] **Step 3: 实现**：`ModeSwitch` 两个圆角块（阅 / 搜），横排时是两个 chip，竖排时上下堆叠 28×28，选中态用 `secondaryContainer`；阅读页不传 `leading`。

- [ ] **Step 4: 跑测试通过**；`flutter test test/features/reader_rail_test.dart` 仍绿（阅读页无开关）。

- [ ] **Step 5: 提交**：`git commit -m "feat(root): add mode switch in section rail"`

### Task 3: 会话数据层（Drift）

**Files:**
- Modify: `lib/data/db/tables.dart`（追加两张表）、`lib/data/db/app_database.dart:8-57`（`schemaVersion = 7` + `if (from < 7)` 建表建索引）、`lib/app/providers.dart`（两个仓储 provider）
- Create: `lib/data/repositories/chat_repository.dart`
- Test: `test/data/chat_repository_test.dart`、`test/data/migration_test.dart`（补 6→7）

**Interfaces:**
- Produces: `ChatThreads` / `ChatMessages` 表（字段见 spec §9，`status` 默认 `'complete'`）；`ChatThreadRepository(AppDatabase)`：`Future<ChatThreadRow> create({String? title})`、`Stream<List<ChatThreadRow>> watchAll()`、`Future<void> delete(String id)`、`Future<void> touch(String id, {String? title})`；`ChatMessageRepository(AppDatabase)`：`Future<ChatMessageRow> append({required String threadId, required String role, required String content, String status = 'complete', String? sourcesJson})`、`Future<void> updateContent(String id, String content, {required String status})`、`List<ChatMessageRow> list(String threadId)`（按 `createdAt`）、`Future<void> markStreamingAsInterrupted()`。

- [ ] **Step 1: 写失败测试**：建库 → 建会话 → 追加两条消息 → `list()` 顺序正确；删除会话后消息为空；`touch` 使 `watchAll()` 首项变为该会话；`markStreamingAsInterrupted()` 把 `status='streaming'` 改成 `'interrupted'`。迁移测试：从 6 版库升级后 `chatThreads`/`chatMessages` 存在。

- [ ] **Step 2: 跑测试确认失败**（表不存在 / 编译错误）。

- [ ] **Step 3: 实现**表、迁移、仓储；`flutter pub run build_runner build --delete-conflicting-outputs` 生成 `app_database.g.dart`。

- [ ] **Step 4: 跑测试通过**（含 `test/data/migration_test.dart`）。

- [ ] **Step 5: 提交**：`git commit -m "feat(data): persist chat threads and messages"`

### Task 4: 搜索配置与 Tavily 实现

**Files:**
- Create: `lib/search/search_hit.dart`, `lib/search/search_provider.dart`, `lib/search/search_config.dart`, `lib/search/tavily_search_provider.dart`
- Modify: `lib/features/settings/settings_page.dart`（新增「联网搜索」区块 + 测试按钮）、`lib/app/providers.dart`
- Test: `test/search/tavily_search_provider_test.dart`、`test/features/settings_page_test.dart`（补区块渲染）

**Interfaces:**
- Produces: `SearchHit({required String title, required String snippet, required String source, String? url, String? locatorJson, String? publishedAt})` + `toJson`/`fromJson`；`abstract class SearchProvider { String get id; bool get isConfigured; Future<List<SearchHit>> search(String query, {int count = 5, CancelToken? cancel}); }`；`SearchConfig({String provider = 'off', String apiKey = ''})` + `SearchConfigStore(SettingsRepository)` 键 `search.provider` / `search.apiKey`；`TavilySearchProvider({required SearchConfig Function() config, required Future<TavilyResponse> Function(TavilyRequest) post})`，默认 transport 用 `dart:io HttpClient` POST `https://api.tavily.com/search`。

- [ ] **Step 1: 写失败测试**：注入假 transport 返回 2 条 results → 解析出 title/url/snippet、`source` 为域名；非 200 抛 `SearchException('HTTP 401: …')`；空 key 时 `isConfigured == false` 且 `search` 抛 `SearchException('未配置联网搜索')`。

- [ ] **Step 2: 跑测试确认失败**。

- [ ] **Step 3: 实现**上述文件；设置页加区块（下拉 `关闭/ Tavily`、Key 输入、「测试搜索」按钮显示「成功：N 条」或错误）。

- [ ] **Step 4: 跑测试通过**。

- [ ] **Step 5: 提交**：`git commit -m "feat(search): add tavily search provider and settings"`

### Task 5: 对话服务（prompt 拼装）

**Files:**
- Create: `lib/search/agent_service.dart`
- Test: `test/search/agent_service_test.dart`

**Interfaces:**
- Produces: `SearchAgentService({required LlmClient client})`，`Stream<String> send({required List<ChatMessage> history, required String userText, List<SearchHit> hits = const [], required CancelToken cancel})`；`class ChatMessage { final String role; final String content; }`；system prompt 常量 `searchSystemPrompt`（中文、不编造、有 hits 时优先引用并给链接、无 hits 时说明可能过时）。

- [ ] **Step 1: 写失败测试**（用 `test/support/fake_llm_client.dart`）：无 hits 时最后一条是 user 文本、system 在首位且不含「检索结果」；有 2 条 hits 时 system 里含两个 url；历史 30 条时拼出的 message 数 ≤ 历史上限且最后一条是当前输入；`cancel.cancel()` 后 stream 不再 yield。

- [ ] **Step 2: 跑测试确认失败**。

- [ ] **Step 3: 实现**：`_buildMessages`（system + 裁剪后的历史 + 当前 user，hits 拼成 `【检索结果】\n1. 标题 — url\n摘要`）；裁剪规则从最新往前累计 ≤ 8000 字，至少保留最后一轮。

- [ ] **Step 4: 跑测试通过**。

- [ ] **Step 5: 提交**：`git commit -m "feat(search): build agent messages with search hits"`

### Task 6: 搜的界面（会话列表 + 消息流 + 输入 + 流式落库）

**Files:**
- Create: `lib/features/search/search_shell.dart`, `lib/features/search/conversation_sidebar.dart`, `lib/features/search/message_list.dart`, `lib/features/search/chat_composer.dart`, `lib/features/search/chat_controller.dart`
- Modify: `lib/features/root/root_view.dart`（搜壳换成 `SearchShell`）、`lib/app/providers.dart`
- Test: `test/features/search_shell_test.dart`

**Interfaces:**
- Produces: `ChatController`（`FamilyAsyncNotifier`，key = threadId 或 `'new'`）：`Future<void> send(String text, {required bool webSearch})`、`void stop()`、`AsyncValue<List<ChatMessageRow>>` 状态、`bool isStreaming`、`String? error`；`SearchShell()`；`ConversationSidebar({required String? activeThreadId, required ValueChanged<String> onSelect, required VoidCallback onNew})`；`ChatComposer({required Future<void> Function(String) onSend, required VoidCallback onStop, required bool streaming, required bool webEnabled, required ValueChanged<bool> onWebChanged})`。

- [ ] **Step 1: 写失败测试**：在「搜」页输入「你好」→ 回车 → 假 `LlmClient` 流式返回 `ok` → 消息区出现「你好」与「ok」→ 侧栏出现一条会话；流式中点「停止」→ 状态变 `interrupted` 且内容保留；未配置模型（`llmConfigProvider` 覆盖为空 key）→ 显示「去设置」；窄屏（`tester.view.physicalSize` 设 900×1600）→ 侧栏在 `Drawer` 里。

- [ ] **Step 2: 跑测试确认失败**。

- [ ] **Step 3: 实现**：桌面 ≥ 900 双栏；消息区 `ListView` + 用户气泡右对齐 / 助手 Markdown 左对齐；输入框 `minLines:1,maxLines:6`，Enter 发送、Shift+Enter 换行；发送时先在 DB 建/取会话、插入 user 行、插入 assistant 行（`streaming`）后节流写；`stop()` 调 `CancelToken.cancel()` 并把 assistant 行置 `interrupted`；`SearchShell` 初始化时 `markStreamingAsInterrupted()`。

- [ ] **Step 4: 跑测试通过**。

- [ ] **Step 5: 提交**：`git commit -m "feat(search): add agent chat shell with streaming and history"`

### Task 7: 联网接入与打磨

**Files:**
- Modify: `lib/features/search/chat_controller.dart`（联网分支）、`lib/features/search/search_shell.dart`（来源条、空态建议、错误重试）、`pubspec.yaml`（`flutter_markdown`）
- Test: `test/features/search_shell_test.dart`（补联网成功/失败用例）

**Interfaces:**
- Consumes: Task 4 的 `SearchProvider`、Task 5 的 `SearchAgentService.send`。
- Produces: 助手消息 `sourcesJson` 落库；「本次未使用联网结果（检索失败/无结果）」灰条 + 重试。

- [ ] **Step 1: 写失败测试**：开「联网」+ 假 provider 返回 1 条 → 请求 messages 的 system 里含该 url，消息下方出现「引用了 1 个来源」；假 provider 抛错 → 仍产生回答，且出现「本次未使用联网结果」。

- [ ] **Step 2: 跑测试确认失败**。

- [ ] **Step 3: 实现**并加 `flutter_markdown` 依赖（`flutter pub add flutter_markdown`，验证版本兼容）。

- [ ] **Step 4: 跑全部测试 + `flutter analyze`** 全绿。

- [ ] **Step 5: 提交**：`git commit -m "feat(search): wire web search into answers"`
