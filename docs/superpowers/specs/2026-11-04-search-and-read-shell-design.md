# 入口分叉：搜（agent 对话）与 阅（书架） — 设计文档

- 日期：2026-11-04
- 状态：待用户评审
- 项目目录：`D:\。git`

## 1. 意图与背景

现在 App 一启动就是书架（`AppShell`：左竖栏 + 分类栏 + 书格），不存在入口页。用户要把它变成**开屏分叉**：

- **搜**：一个通用 agent 对话页，观感对齐主流 agent 产品（会话列表、消息流、流式回答、可联网搜索）。
- **阅**：现在这套书架界面，原样保留，作为"读"的入口。

用户已确认：

- 结构走**方案 A**：入口页 + 两个独立的全屏壳（不是把"搜"塞进现有竖栏）。
- **不记住上次选择**：每次冷启动都回到入口页。
- 在壳内**左上角切换模式**（搜 ↔ 阅）。
- "搜书架里的书"是**后续**加在"阅"上的功能，本期不做；但搜索层要留成接口，届时接同一个位置。

## 2. 目标

1. 冷启动先看到入口页，两个选择：搜 / 阅，点哪个进哪个。
2. 阅 = 现有 `AppShell` 能力不退化（书架、分类、导入、删除、设置、阅读页、蒸馏、陪读全部照旧）。
3. 搜 = 可用的 agent 对话页：
   - 会话落库，左侧会话列表可新建、切换、删除；
   - 流式回答、可中途停止；
   - 消息区支持 Markdown（标题、列表、代码块、链接、表格）；
   - 「联网」开关：打开后先检索再回答，答案里带来源链接。
4. 左上角模式开关在搜 / 阅之间即时切换，切回来时不丢正在进行的流式回答。
5. 未配置模型 / 未配置搜索时，各自给出可点的"去设置"入口，而不是报错白屏。

## 3. 非目标（本期明确不做）

- 搜书架、检索自己的书（后续在"阅"里做）。
- 主流 agent 那种"模型自己决定搜不搜"的多轮 tool-calling 循环（本期用开关式检索，见 §8）。
- 会话重命名、置顶、归档、全文搜索、导出、分享。
- 语音朗读搜的回答（陪读面板的 TTS 不动，也不接到"搜"）。
- 图片/文件上传、多模型切换、端侧向量检索、账号与云同步。
- Web 端适配（仍以 Windows + Android 为目标）。

## 4. 反目标（即使跑起来也算失败）

- **两个壳互相耦合**：为了加"搜"而改动阅读页/书架的数据流，或让"阅"依赖"搜"的路由状态。
- **复用陪读面板的绑书上下文**：`AssistantService.chat()` 的 system prompt 由 `ReadingContext` 拼成，直接拿来当通用对话会带进书名/章节，答案跑偏。
- **会话只在内存里**：关掉应用会话就没了，做不出主流 agent 的会话列表观感。
- **联网开关对任何 OpenAI 兼容后端都不可用**：本期不依赖 tool calling，只用普通 chat-completions，换模型不需要改代码。
- **冷启动变慢**：入口页必须是纯 UI，不做网络探测、不预加载模型。

## 5. 约束

- 现有栈：Flutter 3.47 / Dart 3.13、Riverpod 3、Drift 2、`dart:io` HTTP（`OpenAiLlmClient`），无 http 包、无 Markdown 包。
- 平台：Windows 桌面 + Android；窄屏（手机）必须可用，不能出现三列挤压。
- 数据库已有迁移链（`schemaVersion = 6`），新增表必须走 `onUpgrade`，不允许破坏老库。
- 现有测试 334 个全绿（README 记录），新增功能必须补测试并保持 `flutter analyze` 干净。
- API Key 目前明文存 `settings` 表（已知限制），本期沿用同一方式，不引入凭据库。

## 6. 方案对比（已选 A）

| 方案 | 做法 | 取舍 |
|---|---|---|
| **A（选中）** | 入口页 + 两个独立全屏壳；壳内左上角模式开关 | 两套界面互不牵制，搜有自己的会话列表位置；代价是多一层根路由与一个壳 |
| B | 把"搜"做成现有竖栏里的一个新分区 | 改动最小；但竖栏 + 会话列表 + 消息区三列，手机端挤，观感也不像"分叉" |
| C | 记住上次选择，冷启动直达 | 少点两下；与"每次都要自己选"的诉求冲突，已否决（不叠在 A 上） |

## 7. 界面形态

### 7.1 根视图

`BookApp.home` 从 `AppShell` 换成 `RootView`：

- `modeProvider`（`AppMode?`，`null` = 还没选）初始为 `null` → 显示 `LauncherPage`。
- 选了之后显示 `IndexedStack(index: mode)`，两个壳同时活着：切模式不销毁"搜"的流式回答和滚动位置，也不重建书架的滚动状态。
- **懒构建**：`RootView` 自己维护 `Set<AppMode> built`，只有访问过的壳才真正 build（未访问的用 `Offstage` 占位）。选「搜」时不会立刻拉起书架的 Drift 订阅，入口页与冷启动保持轻（对齐 §4）；一旦构建就常驻，状态天然保活。
- `RootView` 不做路由跳转，只切 `IndexedStack` 的 index；因此没有"返回入口页"的路径——冷启动必然回到入口页（符合"不记住上次"）。

### 7.2 入口页 `LauncherPage`

- 居中：一枚小的品牌标记、一句标题（如「今天想做什么？」）、两张卡片。
- 宽屏（≥ 720dp）左右并排；窄屏上下堆叠。卡片是整块可点区域 + 键盘焦点。
- 卡片内容：大图标 + 大字「搜」/「阅」+ 一行说明（「问点什么，也可以让它上网找」/「继续读你书架上的书」）。
- 纯本地渲染，不读数据库、不请求网络。

### 7.3 左上角模式开关 `ModeSwitch`

- 一个 2 段控件（阅 | 搜），高亮当前模式，点另一段切换；`Key('mode-switch-read')` / `Key('mode-switch-search')`。
- 桌面竖栏里竖排（64px 宽，两枚 28×28 圆角块），"搜"页顶栏里横排。实现上是给 `SectionRail` 加一个可选插槽（`leading`），阅壳传 `ModeSwitch`，阅读页不传。
- 阅读页（`ReaderPage` / `PdfReaderPage` 的 `ReaderRail`）**不显示**模式开关（用户已确认）：它是压在根路由之上的独立路由，切 index 不会让它消失，显示开关会出现"点了没反应"。要看"搜"得先退出阅读页回到书架。
- 桌面快捷键：`Ctrl+1` 阅、`Ctrl+2` 搜（`Shortcuts`/`Actions`）；Android 走实体返回键 = 不变（不看作为"退回入口页"）。

### 7.4 搜的壳 `SearchShell`

桌面（≥ 900dp）两栏：

- 左：`ConversationSidebar`（宽 264）——顶部「新对话」按钮，下面按 `updatedAt` 倒序的会话列表；每行标题（首条用户消息截断 24 字）、末次时间；hover/长按出「删除」。
- 右：对话区——顶栏（`ModeSwitch` + 会话标题 + 设置图标）、消息流、输入区。

窄屏（< 900dp）：侧栏收进 `Drawer`，顶栏左侧是汉堡按钮 + 模式开关。

消息流：

- 用户消息右对齐、气泡、最大宽 640；助手消息左对齐、无气泡底色、Markdown 渲染、最大宽 760。
- 助手消息底部一行：复制、（流式中）停止已由输入区承担；来源列表折叠在「引用了 N 个来源」条里，展开是标题 + 域名链接。
- 流式时显示光标块；首个 token 到达前显示「正在思考…」，检索阶段显示「正在搜索「…」…」。
- 空会话：标题问候 + 3 个示例提示（点了直接填入输入框，不自动发送）。

输入区：

- 圆角容器，`TextField` `minLines: 1, maxLines: 6`；Enter 发送、Shift+Enter 换行（桌面）；移动端发送按钮。
- 左侧「联网」chip（默认关，状态存在设置里，切页保留），未配置搜索时点开提示去设置。
- 发送按钮在流式中变成「停止」（`CancelToken.cancel()`）。

错误与未配置：

- 未配置模型：对话区中央提示 + 「去设置」（复用 `SettingsPage`），输入区禁用。
- 请求失败：消息流底部红字 + 「重试」；已收到的部分内容保留。

## 8. 联网搜索（本期形态）

开关式，一轮完成：

1. 用户开启「联网」并发送。
2. `SearchProvider.search(query)` 取 5 条结果（标题 / 链接 / 摘要 / 发布时间）。
3. 结果整理成文本块塞进 system 消息；附一条硬约束：「如果检索结果不足以回答，就直说；引用时给链接」。
4. `LlmClient.streamChat` 走普通 chat-completions（不用 tool calling），因此对任何 OpenAI 兼容端点都成立。
5. 答案里的链接在 Markdown 里正常渲染；引用条展示本次用到的 hits。

接口（为"搜书架"预留，因此契约做中性，不写死成网络检索引擎）：

```dart
/// 一条可引用的材料。联网检索落 url；本地搜书落 locator（章节 + 字符偏移）。
class SearchHit {
  final String title;
  final String snippet;
  final String source;       // 域名，或书名
  final String? url;         // 本地结果为空
  final String? locatorJson; // {'bookId','chapterIndex','offset'}，联网结果为空
  final String? publishedAt;
}

abstract class SearchProvider {
  String get id;                       // 'tavily' | 'library' （后者本期只占位）
  bool get isConfigured;               // 本地实现恒为 true
  Future<List<SearchHit>> search(String query, {int count = 5, CancelToken? cancel});
}
```

- 引用条与 `sourcesJson` 只依赖这五个字段（`url` 可空时展示为纯文本），未来"搜书架"接同一接口、同一 UI。
- 首个实现 `TavilySearchProvider`：`POST https://api.tavily.com/search`，body `{api_key, query, max_results, search_depth: "basic"}`，解析 `results[].title/url/content`。
- 配置沿用 `settings` 表：`search.provider`（`off`/`tavily`）、`search.apiKey`，由 `SearchConfigStore` 读写（照 `LlmConfigStore` 的写法）。
- 设置页新增「联网搜索」区块：provider 下拉、API Key、「测试搜索」（搜 `ping`，1 条，成功提示条数，失败显示 HTTP 状态）。
- **检索失败或 0 结果**：不中断这一轮，降级为不联网继续回答，并在消息里附一条灰色提示「本次未使用联网结果（检索失败/无结果）」，附「重试」按钮；重试重跑整轮（含重新检索），不复用旧 hits。模型请求本身失败仍按 §7.4 处理（红字 + 重试，保留已收到内容）。

## 9. 数据模型（Drift）

新增两张表，`schemaVersion` 6 → 7，`onUpgrade` 里 `if (from < 7)` 建表建索引：

```dart
@DataClassName('ChatThreadRow')
@TableIndex(name: 'chat_threads_updated', columns: {#updatedAt})
class ChatThreads extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

@DataClassName('ChatMessageRow')
@TableIndex(name: 'chat_messages_thread', columns: {#threadId, #createdAt})
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get threadId => text()();
  TextColumn get role => text()();          // 'user' | 'assistant'
  TextColumn get content => text()();
  TextColumn get sourcesJson => text().nullable()();  // 本次回答用到的 SearchHit 列表
  TextColumn get status => text().withDefault(const Constant('complete'))(); // streaming | complete | interrupted
  DateTimeColumn get createdAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}
```

- 会话标题：首条用户消息去换行、截断 24 字；不调模型生成标题。
- **流式落库**：首个 token 到达时插入 assistant 行（`status = 'streaming'`），之后节流写库（≥300ms 或累计 ≥2KB），正常结束置 `complete`，用户点「停止」或请求异常置 `interrupted` 并保留已出内容；应用启动时把残留的 `streaming` 一律改成 `interrupted`（覆盖关窗、被杀的情况），界面上显示半截内容 + 「已中断」标注。
- **不随界面切换取消流**：切到「阅」或切到另一个会话，正在跑的流继续在后台写库；只有「停止」和关闭应用会中断它。因此对话状态放在会话级 controller（`keepAlive`）而不是页面 `State` 里。
- 进入「搜」默认新建一个未落库的空会话（不恢复上次会话，与"不记住上次"一致）；历史会话只从侧栏点开。
- 删除会话：事务里先删消息再删会话（不使用外键，沿用现有表的写法）。
- 仓储 `ChatThreadRepository` / `ChatMessageRepository`，放 `lib/data/repositories/`，由 `providers.dart` 暴露；写操作后 `updatedAt` 前进，侧栏用 `watchAll()` 流式刷新。

## 10. 服务层

- `lib/search/agent_service.dart`：`SearchAgentService`
  - `Stream<String> send({required List<ChatMessage> history, required String userText, List<SearchHit> hits = const [], required CancelToken cancel})`
  - system prompt：中文、直接回答问题、不编造、有检索结果时优先使用并给链接、没有结果就基于自身知识并说明可能过时。
  - 历史裁剪：从最新往前取，累计不超过 8000 字（字符数），至少保留最后 1 轮。
- 不复用 `AssistantService`（它绑 `ReadingContext`），但复用 `LlmClient` / `OpenAiLlmClient` / `CancelToken`——流式、取消、超时、错误文案都已具备。
- 依赖注入：`searchAgentProvider`、`searchProviderFactoryProvider`（按 `search.provider` 返回实现，`off` 返回 `UnconfiguredSearchProvider`）。

## 11. 新增依赖

- Markdown 渲染：优先 `flutter_markdown`；实施时验证与当前 Flutter/Dart 版本兼容性与维护状态，不行就换 `gpt_markdown` 或 `markdown_widget`（选型结论写进提交说明）。
- 不新增 HTTP 包：搜索走 `dart:io HttpClient`，与 `OpenAiLlmClient` 一致。

## 12. 测试

- 单元：`TavilySearchProvider` 解析（假 `HttpClient`/注入 transport，参考 `test/distill/openai_llm_client_test.dart`）；`SearchConfigStore` 读写；`SearchAgentService` 的 messages 拼装（含/不含检索结果、历史裁剪边界）；chat 仓储增删查与 `updatedAt` 推进；迁移测试补 6→7（`test/data/migration_test.dart`）。
- Widget：入口页两张卡各进对应壳；`ModeSwitch` 双向切换；搜索页发送 → 假 `LlmClient` 流式出字 → 落库 → 侧栏出现会话；流式中「停止」能中断且保留已出内容；未配置模型显示「去设置」；窄屏侧栏走 Drawer。
- 回归：现有 334 个测试保持全绿；`flutter analyze` 干净。
- 预期内的既有测试改动：`test/app/app_shell_test.dart` 现在直接 pump `BookApp()` 并断言书架，加入口页后要先点「阅」，该用例按新流程改（不算回归）。

## 13. 里程碑

1. **M1 入口页 + 模式开关**：`RootView`/`LauncherPage`/`ModeSwitch`，"搜"先是空壳占位；"阅"完全不变。
2. **M2 会话与对话**：Drift 表 + 迁移 + 仓储 + `SearchAgentService`（不联网）+ 搜索页消息流/输入/停止/复制。
3. **M3 联网**：`TavilySearchProvider` + 设置区块 + 引用条 + 检索阶段提示。
4. **M4 打磨**：Markdown 完整样式、示例提示、错误与重试、窄屏适配、测试补齐。

每个里程碑可独立运行、独立提交。

## 14. 留给实施者的决定

- Markdown 包最终选型（§11）。
- 断点数值（720 / 900dp）可按实测微调。
- 引用条的视觉形式（条 vs 卡片）。
- 检索结果如何拼进 prompt 的具体格式与条数上限（5 条起步）。
- 是否给助手消息加"重新生成"（本期可选，不阻塞）。
