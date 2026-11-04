# 桌宠左键说话 / 右键气泡聊天 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让阅读页的桌宠左键即兴说一句关于当前页的话，右键在它旁边弹出气泡式的多轮对话面板。

**Architecture:** 新增一个纯展示的 `CompanionChatPanel` 和一个持有按章对话状态的 `CompanionChatController`；`CompanionPresence` 把左键交给 `onSpeak`、右键交给 `onOpenChat`；阅读页负责"点一次取一句"的 loader 与面板的定位。

**Tech Stack:** Flutter / Dart 3.13、flutter_riverpod、现有 `AssistantService` 与 `ReadingContext`。

**Spec:** docs/superpowers/specs/2026-11-04-companion-chat-design.md

## Global Constraints

- 不新增依赖。
- 所有 Timer / AnimationController 必须在 dispose 取消；禁止无限循环动画（`pumpAndSettle` 必须能结束）。
- 测试里动画面板走 `FLUTTER_TEST` 或直接不播动画。
- 面板宽度 `min(320, maxWidth - 24)`，不越界。
- 每章对话最多保留 20 条（10 轮）。

## Review Focus

- 右键在 Flutter 桌面把 `onSecondaryTapDown` 与 `onTap` 同时命中时不能把气泡开合也触发一次（两个回调互斥）。
- 左键连点：上一句还在生成时再点一下，不能并发两次请求，也不能把气泡卡在「嗯……」。
- 切章后聊天面板标题与历史要跟着换，但切回旧章能看到原来的对话。
- 流式回复中途关闭面板：不能抛 "setState after dispose"，流要能安全结束。
- 窄窗（360 宽）下聊天面板与桌宠、翻页热区不互相遮挡。

---

### Task 1: CompanionChatPanel（纯展示）

**Files:**
- Create: `lib/features/companion/companion_chat.dart`
- Test: `test/features/companion_chat_test.dart`

**Interfaces:**
- Consumes: `ChatMessage`（`package:hackathon_reading/assistant/assistant_service.dart`）。
- Produces: `CompanionChatPanel({super.key, required String title, required List<ChatMessage> messages, required String streaming, required bool busy, required ValueChanged<String> onSend, required VoidCallback onClose})`。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('lists reader and companion bubbles', (tester) async {
  await tester.pumpWidget(_host(CompanionChatPanel(
    title: '陪读 · 第一部分',
    messages: const [
      ChatMessage.user('这一页在讲什么？'),
      ChatMessage.assistant('外婆在挑鞋，母亲在讲她小时候。'),
    ],
    streaming: '',
    busy: false,
    onSend: (_) {},
    onClose: () {},
  )));
  expect(find.text('这一页在讲什么？'), findsOneWidget);
  expect(find.text('外婆在挑鞋，母亲在讲她小时候。'), findsOneWidget);
});

testWidgets('sends what the reader typed', (tester) async {
  final sent = <String>[];
  await tester.pumpWidget(_host(CompanionChatPanel(
    title: 't', messages: const [], streaming: '', busy: false,
    onSend: sent.add, onClose: () {},
  )));
  await tester.enterText(find.byKey(const Key('companion-chat-input')), '她为什么生气？');
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
  expect(sent, ['她为什么生气？']);
});

testWidgets('shows the streaming tail and disables send while busy', (tester) async {
  await tester.pumpWidget(_host(CompanionChatPanel(
    title: 't', messages: const [], streaming: '外婆正', busy: true,
    onSend: (_) {}, onClose: () {},
  )));
  expect(find.textContaining('外婆正'), findsOneWidget);
  expect(tester.widget<IconButton>(find.byKey(const Key('companion-chat-send'))).onPressed, isNull);
});
```

- [ ] **Step 2: 运行确认失败**：`flutter test test/features/companion_chat_test.dart` → 编译失败（找不到 CompanionChatPanel）。

- [ ] **Step 3: 实现面板**：`Material` 圆角 16 + elevation 6，宽 320 由外层约束；顶部一行标题 + `IconButton(Key('companion-chat-close'))`；中间 `ListView`（`Key('companion-chat-messages')`，自动滚到底）；底部 `TextField(Key('companion-chat-input'), textInputAction: TextInputAction.send, onSubmitted: _submit)` + `IconButton(Key('companion-chat-send'))`（`busy` 时 onPressed 为 null）。气泡：读者右对齐 `primaryContainer`，桌宠左对齐 `surfaceContainerHighest`，圆角 12，`maxLines: 6`。

- [ ] **Step 4: 运行测试通过**：`flutter test test/features/companion_chat_test.dart` → 3 passed。

- [ ] **Step 5: 提交**：`feat(companion): add the bubble chat panel`

---

### Task 2: CompanionChatController（按章会话 + 流式）

**Files:**
- Create: `lib/features/companion/companion_chat_controller.dart`
- Test: `test/features/companion_chat_controller_test.dart`

**Interfaces:**
- Consumes: `assistantServiceProvider`（`Future<AssistantService>`）、`personaModeProvider`（`PersonaMode`）、`AssistantService.chat(ReadingContext, List<ChatMessage>, String, {PersonaMode persona})`、`ChatMessage.user/assistant`。
- Produces:
  - `class CompanionChatController extends ChangeNotifier { CompanionChatController(Ref ref); List<ChatMessage> messagesFor(String chapterId); String get streaming; bool get busy; Future<void> ask(String chapterId, ReadingContext context, String text); }`
  - `const companionChatHistoryLimit = 20;`
  - `const companionChatFailureLine = '我这会儿有点卡，再问我一次？';`

- [ ] **Step 1: 写失败测试**（用 `_FakeAssistant` 覆盖 `assistantServiceProvider`）

```dart
test('keeps a separate thread per chapter', () async { ... expect(c.messagesFor('c1').length, 2); expect(c.messagesFor('c2'), isEmpty); });
test('streams the answer into streaming', () async { final f = c.ask('c1', ctx, '问'); expect(c.streaming, isNotEmpty); expect(c.busy, isTrue); await f; expect(c.messagesFor('c1').last.text, '答完了。'); });
test('falls back to a soft line when the stream fails', () async { ... expect(c.messagesFor('c1').last.text, companionChatFailureLine); });
test('trims the oldest turns', () async { ... 12 轮后长度 <= 20 });
```

- [ ] **Step 2: 运行确认失败**：`flutter test test/features/companion_chat_controller_test.dart`。

- [ ] **Step 3: 实现**：`ask` 里 `if (_busy) return;` 置 busy、清空 streaming、`notifyListeners()`；取 service，`service.isConfigured` 为假直接写入 `companionChatFailureLine` 作为桌宠气泡；否则 `await for (final chunk in service.chat(context, history, text, persona: persona))` 累加 + notify；完成或异常后把结果写进 `_sessions[chapterId]`，`_trim`，busy=false，notify。

- [ ] **Step 4: 运行测试通过**。

- [ ] **Step 5: 提交**：`feat(companion): keep a per-chapter chat thread for the pet`

---

### Task 3: 右键 / 长按 + 左键说话接线

**Files:**
- Modify: `lib/features/companion/companion_body.dart`、`companion_avatar.dart`、`companion_presence.dart`
- Test: `test/features/companion_presence_test.dart`、`test/features/companion_avatar_test.dart`

**Interfaces:**
- Produces:
  - `CompanionBody({..., this.onSecondaryTap})`、`CompanionAvatar({..., this.onSecondaryTap})`（`VoidCallback?`）。
  - `CompanionPresence({..., this.onSpeak})` —— `Future<String?> Function()?`；左键每次点击都调用它；右键触发 `onOpenChat`。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('speaks a fresh line on every left click', (tester) async {
  var calls = 0;
  await tester.pumpWidget(_host(CompanionPresence(height: 160, autoGreet: false, onSpeak: () async { calls++; return '第 $calls 句'; })));
  await tester.tap(find.byKey(const Key('companion-avatar')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('companion-avatar')));
  await tester.pumpAndSettle();
  expect(calls, 2);
});

testWidgets('right click opens the chat without toggling the bubble', (tester) async {
  var opened = 0;
  await tester.pumpWidget(_host(CompanionPresence(height: 160, autoGreet: false, onOpenChat: () => opened++, onSpeak: () async => null)));
  await tester.tap(find.byKey(const Key('companion-avatar')), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  expect(opened, 1);
});
```

- [ ] **Step 2: 运行确认失败**。

- [ ] **Step 3: 实现**：`CompanionBody` 的 `GestureDetector` 加 `onSecondaryTapDown: (_) => onSecondaryTap?.call()` 与 `onLongPress: onSecondaryTap`；`CompanionAvatar` 转发；presence 的 `_handleAvatarTap` 改为：给了 `onSpeak` 就 `_open()` 先显示「嗯……」，再 `await onSpeak()` 替换文案；超时/空仍用 `widget.greeting`。

- [ ] **Step 4: 运行测试通过**（两个文件一起跑）。

- [ ] **Step 5: 提交**：`feat(companion): left click speaks, right click opens the chat`

---

### Task 4: 阅读页接入

**Files:**
- Modify: `lib/features/reader/reader_page.dart`
- Test: `test/features/reader_page_test.dart`、`test/features/reader_companion_test.dart`

**Interfaces:**
- Consumes: Task 1–3 的全部接口。
- Produces: 私有 `_speakLine()`、`_chatOpen`、`_chatController`；`_withAvatar` 内新增 `CompanionChatPanel` 的 `Positioned(right: 12, bottom: height + 36)`。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('right click opens the bubble chat', (tester) async {
  await pumpReader(tester, 'b1');
  await tester.tap(find.byKey(const Key('companion-avatar')), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('companion-chat-panel')), findsOneWidget);
});

testWidgets('a question in the chat gets an answer bubble', (tester) async {
  // 用 assistantServiceProvider.overrideWith((ref) async => _EchoAssistant())
  ...enterText + send... expect(find.textContaining('桌宠回答说'), findsOneWidget);
});
```

- [ ] **Step 2: 运行确认失败**。

- [ ] **Step 3: 实现**：阅读页持有 `late final CompanionChatController _chatController`；`_openChat()` 切换 `_chatOpen`；`onSpeak: () => _speakLine()` 直接调 `ref.read(companionGreeterProvider)(CompanionGreetingRequest(...))`（去掉 `_greetings` 缓存）；面板 `title: '陪读 · ${chapter.title}'`，`onSend: (text) => _chatController.ask(chapter.id, context, text)`；`_chatController` 在 dispose 释放。

- [ ] **Step 4: 运行测试通过**（reader_page_test + reader_companion_test）。

- [ ] **Step 5: 提交**：`feat(companion): wire the pet chat into the reader`

---

### Task 5: 验证与演示

- [ ] `dart analyze lib test` → No issues found!
- [ ] `flutter test` → 全绿（若 `companion_panel_test` 仍因另一路 persona 改动失败，记录在案并只跑本切片相关文件）
- [ ] `flutter build windows --debug` → 成功
- [ ] 启动应用：右键桌宠弹面板、发一句话看到气泡回复、左键听到新的一句；截图存 `docs/superpowers/screenshots/`
- [ ] 更新 `.superpowers/sdd/2026-11-04-companion-avatar/progress.md` 与设计稿状态
