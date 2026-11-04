# 陪读桌宠：左键说话 / 右键气泡聊天（设计稿）

日期：2026-11-04 · 分支 feature/companion-avatar · 状态：待确认

## 1. 意图

读者在阅读页旁边有一个会动的 Q 版桌宠。现在点它只会打开底部「陪读」大面板。
希望改成更像桌宠的交互：

- **左键点它**：它自己开口说一句——说的是这一页正在发生的事，或者就是一句打招呼。
- **右键点它**：在它旁边弹出一个小气泡对话框，读者可以像聊天一样问它问题，模型回复也以气泡的形式一条条冒出来。

## 2. 目标（本期）

1. 左键：每次点击都请模型按「当前书 + 当前章 + 当前页 + 读者位置」说一句新的话；等待期间气泡先显示「嗯……」，拿到就把文字换掉；失败或超时（4 秒）回落到 `companionGreetingFallbacks` 里的一句问候。
2. 右键：在桌宠右上方弹出浮动小面板（宽 320，最高约阅读区 60%），含消息气泡列表 + 输入框 + 发送按钮；Enter 发送；点面板外或 Esc 收起。
3. 面板里的对话**按章一轮**：同一章内反复开关面板都接着聊；翻页不换话题；**切章即开新对话**（旧的留到内存里，回到该章还能看到）。
4. 模型回复流式进入最后一条气泡；出错时该气泡变成一句温和的兜底话，不弹 SnackBar。
5. 触屏设备没有右键：长按桌宠等价于右键。

## 3. 非目标（本期）

- 不做 TTS 朗读（底部陪读面板已有；这里只做文字气泡）。
- 不落盘：对话只活在这次阅读会话里，退出应用即失。
- 不改造底部 CompanionPanel 与侧栏的现有入口。
- 不做多轮记忆压缩、不调用 summarizeChapter。

## 4. 约束

- 现有 `CompanionPresence` 的 6 秒自动冒泡、翻页惊一下、说话挥手都要保持。
- 动画/定时器不能用无限循环，`pumpAndSettle` 必须能结束。
- 浮动面板必须落在阅读页 `_withAvatar` 的 Stack 内，不能盖住翻页热区的点击（面板本身可点，面板外穿透）。
- 窄窗（< 420 逻辑宽）时面板宽度收缩到 `maxWidth - 24`，不越界。

## 5. 方案对比

- **A 贴桌宠的悬浮面板（选中）**：在阅读页 Stack 里加一层 `Positioned`，锚在桌宠右上方；复用 `AssistantService.chat` 与 `ReadingContext`。改动集中在 companion 目录，底部大面板不动。
- B 改造底部 CompanionPanel 为气泡样式：位置在页面底部，跟「在桌宠旁边」的预期不符，还要动已有大量测试。
- C 全屏聊天页：离开阅读上下文，切回来打断阅读。

## 6. 设计

### 6.1 组件

- `lib/features/companion/companion_chat.dart`
  - `CompanionChatPanel({required this.title, required this.messages, required this.streaming, required this.busy, required this.onSend, required this.onClose})`
  - 纯展示：气泡列表（读者右对齐 `primaryContainer`，桌宠左对齐 `surfaceContainerHighest`，带小尾巴）、流式气泡、输入框、发送/关闭按钮。
  - Key：`companion-chat-panel`、`companion-chat-input`、`companion-chat-send`、`companion-chat-close`、`companion-chat-messages`。
- `lib/features/companion/companion_chat_controller.dart`
  - `CompanionChatController extends ChangeNotifier`：`Map<String, List<ChatMessage>> _sessions`（key = chapter id）、`bool get busy`、`String get streaming`、`List<ChatMessage> messagesFor(String chapterId)`、`Future<void> send(...)`。
  - `send` 走 `assistantServiceProvider` + `personaModeProvider`，把当前章上下文 + 历史 + 新问题交给 `chat()`，逐块累加到 `streaming` 并 `notifyListeners`；流结束后把 `ChatMessage.assistant(text)` 写进该章历史；异常时写入兜底句「我这会儿有点卡，再问我一次？」。
  - 历史裁剪：每章最多保留最近 20 条（10 轮）。
- `CompanionPresence` 新增 `onSpeak`（`Future<String?> Function()?`）与 `onOpenChat` 语义调整：
  - 左键 → `onSpeak`（每次点击都重新取一句）；没有 `onSpeak` 时退回原来的开合气泡。
  - 右键 / 长按 → `onOpenChat`。
- `CompanionAvatar` / `CompanionBody` 增加 `onSecondaryTap`（`GestureDetector.onSecondaryTapDown`）与长按，转发给 presence。
- `reader_page.dart`：
  - `_speakLine()`：直接调 `companionGreeterProvider`（**不再按章缓存**），返回前 bubble 显示占位文本。
  - `_openChat()` / `_chatOpen` 状态；`_withAvatar` 的 Stack 内再加 `Positioned(right: 12, bottom: height + 36)` 的 `CompanionChatPanel`，宽度 `min(320, constraints.maxWidth - 24)`。
  - 章切换时 `_chatController` 不动（历史按章隔离），面板标题显示当前章序号。

### 6.2 文案

- 左键占位：「嗯……」
- 兜底问候：`『读到哪儿了？』『这一页好看吗？』『我在呢，随时问我。』`（轮换取，避免连续三次一样）
- 出错兜底：「我这会儿有点卡，再问我一次？」

### 6.3 测试

- `test/features/companion_chat_test.dart`：输入框发送触发回调、读者/桌宠气泡左右分列、流式文本渲染、busy 时禁用发送。
- `test/features/companion_chat_controller_test.dart`：按章隔离、流式累加、错误兜底、历史裁剪。
- `test/features/companion_presence_test.dart`：左键连续两次都触发 `onSpeak`；右键触发 `onOpenChat` 且不切换气泡。
- `test/features/reader_page_test.dart`：右键桌宠出现 `companion-chat-panel`；在面板里发一句话后出现模型回复气泡；左键弹出一句新话。

## 7. 留给实现者

- 面板的入场动画（60~120ms 淡入 + 轻微位移）与收起动画，注意不要用无限循环。
- 面板与输入框的焦点：打开时聚焦输入框；Esc 关闭。
- 气泡长文本换行、最多显示 6 行，超出可滚动。
