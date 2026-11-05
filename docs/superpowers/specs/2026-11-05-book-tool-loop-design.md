# 搜壳工具循环：让模型自己翻书 — 设计文档

- 日期：2026-11-05（v2，含 builder check 修订）
- 状态：待用户评审
- 项目目录：`D:\。git`

## 1. 意图与背景

「搜」壳现在能绑定一本书（`SearchBookNotifier`），但模型回答时只看得到蒸馏摘要和**提前选好的 2 段原文**。

选原文的逻辑在 `lib/search/book_context.dart:147` 的 `_excerpts()`：用**用户问题**的 bigram 跟「章节标题 + 蒸馏出的章节 gist」求交集，取前 2 章各截 1200 字，在模型开口之前就定死了。后果：

- 问题里不含原文词汇时（如「这本书里反复出现的雨意味着什么」），交集为空 → 一段原文都不给 → 模型只能拿摘要猜。
- 反过来，能不能命中完全取决于 gist 写得好不好，与正文无关。

用户的原话是：**「让他会调用工具根据蒸馏的内容去我选的书里搜索来回答我的问题」**——先看蒸馏判断方向，再决定翻哪一章。这刚好把检索的顺序倒了过来：检索发生在模型知道自己要找什么之后。

顺带解决另一件事：这是这个 app 第一个真正的 agent 循环（ReAct），也是"这算不算 agent"这个问题的实证答案。**它不是为标签做的，但标签会自己出现。**

用户已确认的两点：

1. 走**方案一（真 tool calling）**，不做自查询、不只优化预检索。
2. **过程要可见**：检索步骤显示在回答上方。

## 2. 目标

1. 绑定书后，模型可以调用只读工具在**当前这本书**里检索原文，多步直到能回答。
2. 每个检索步骤在 UI 上可见（进行中显示、结束后保留、重开历史会话仍在）。
3. 回答质量在"预检索选错片段"的那类问题上可观察地变好（须给出前后对比的例子）。
4. 端点不支持 tool calling 时**不倒退**：自动降级为现有单轮 + 预检索，并在消息上标注。
5. 步数、工具输出、总时长都有硬上限，循环不会失控。

## 3. 非目标（本期明确不做）

- **写操作**（`add_highlight` / 加书签）：要确认 UI，且要处理"重新导入后全书偏移失效"，本期只读。
- 把工具接到陪读面板（`ReadingContext` 那条链路）：下一期，且要先解决不剧透的结构性边界。
- 流式 tool_calls（`delta.tool_calls` 增量解析）：见 §6 的方案取舍，本期走非流式决策轮。
- 向量检索 / 嵌入模型 / 端侧索引：bigram + 两阶段打分够用，不新增依赖。
- 网页检索与书内检索的联动策略（两个开关同时开时如何取舍）：本期各自独立。
- 跨书检索、书单对比。

## 4. 反目标（即使跑起来也算失败）

- **让现有用户变慢或变差**：没有工具能力的端点、未蒸馏的书、超大书，都必须有明确降级，不能出现"以前能答现在转圈"。
- **过程不可见或不可复盘**：答案出来了但说不清它翻了哪几章，等于把 agent 做成了黑盒——这正是用户要避免的。
- **循环失控**：同一参数重复调用、步数不设上限、工具输出不设预算。
- **把原文塞进库**：`stepsJson` 只存参数、命中数和章号，不存原文片段。
- **为工具而工具**：单轮就能答好的问题（比如"这本书讲什么"），不该被一段看不见的检索拖慢。

## 5. 约束

- 现有栈不变：Flutter 3.47 / Dart 3.13、Riverpod 3、Drift（`schemaVersion = 12`）、`dart:io` HTTP、无新增依赖。
- 所有 LLM 出口仍是 `LlmClient`（`lib/distill/llm/llm_client.dart`）。`streamChat` 有 1 处（搜）＋ 4 处（`openai_assistant_service.dart`）调用，**签名不能破坏**；`test/` 下有 6 个类 `implements LlmClient`（`test/support/fake_llm_client.dart`、`search_shell_test.dart` ×4、`settings_page_test.dart`、`distill_pipeline_test.dart`），所以 **`completeTurn` 必须在抽象类里带默认实现**（`throw UnsupportedError`），否则这 6 个假实现全编译不过。
- 现有 608 个测试保持全绿，`flutter analyze` 干净。
- 表结构变更必须走 `onUpgrade`（12 → 13），不允许破坏老库。
- Windows 桌面 + Android 都要能用；工具循环期间用户点「停止」必须立刻中断并保留已有内容（`CancelToken` 已具备）。
- 上游是任意 OpenAI 兼容端点（默认 `https://api.deepseek.com/v1`，模型 `deepseek-chat`），不能假设支持 `parallel_tool_calls`、`strict` schema 或流式工具调用；**但必须假设一次响应可能带回多个 `tool_calls`**。
- 章正文读取走 `ChapterRepository.getContent(bookId, chapterIndex)`，**chapterIndex 是 0 基**；工具参数里的章号是 1 基，转换在工具箱内部完成，不许泄漏到提示词或 UI。

## 6. 方案对比（已选 A）

前提：用户要的是真 tool calling，不是"看起来像"。真正的分歧在**决策轮怎么发**。

| 方案 | 做法 | 取舍 |
|---|---|---|
| **A（选中）** | 决策轮非流式（`tools` + 非流式响应），最终答案走现有 `streamChat` 流式；步骤以 UI 行呈现 | 只扩 JSON 请求/响应，不碰 SSE 解析；任何"支持 tools 但不支持流式 tools"的端点也能用；用户仍看得见每一步。代价：看不到模型在两轮之间的"心里话" |
| B | 全流式：解析 `delta.tool_calls` 增量、按 index 累积 | 体验最好（能看见它边想边说）；但要改 `sse.dart`，且本地小模型/中转端点对流式 tool_calls 支持参差，风险最高 |
| C | 自查询：让模型先吐 `{"query": ...}`，代码检索后二次请求 | 改动最小、最兼容；但模型看完结果不能改主意，"多步"是假的——不满足"真循环"这个前提 |

选 A 的理由：用户要的"过程可见"由 §8.3 的步骤行满足，不需要流式 tool_calls；而 A 把最脆的部分（SSE 协议扩展）整个绕开了。B 作为后续增强保留：A 落地后，若端点普遍支持，再把决策轮换成流式只影响 `OpenAiLlmClient` 一处。

## 7. 工具契约

两个工具，**每个都对应一个现在做不到的动作**：

```dart
// search_in_book —— 现在完全没有的能力
{
  "name": "search_in_book",
  "description": "在读者选中的这本书里检索原文片段。先用【蒸馏】判断可能在哪几章，"
                 "再考虑填 chapter 缩小范围。返回按相关度排序的片段，每段带章号和字符偏移。",
  "parameters": {
    "type": "object",
    "properties": {
      "query":   {"type": "string",  "description": "检索词或短句，2~12 字，一次只查一个点"},
      "chapter": {"type": "integer", "description": "只查这一章（从 1 开始）。不填则查全书"},
      "limit":   {"type": "integer", "description": "返回几段，默认 3，最多 5"}
    },
    "required": ["query"]
  }
}

// get_chapter —— 现在只能靠预检索碰运气
{
  "name": "get_chapter",
  "description": "读某一章的正文切片。用于确认检索到的片段前后文，或核对引文。",
  "parameters": {
    "type": "object",
    "properties": {
      "chapter":   {"type": "integer", "description": "章号，从 1 开始"},
      "offset":    {"type": "integer", "description": "章内起始字符偏移，默认 0"},
      "max_chars": {"type": "integer", "description": "最多返回多少字，默认 2000，上限 3000"}
    },
    "required": ["chapter"]
  }
}
```

**不做 `get_annotation`**：读者的标注和陪读纪要已经通过 `BookMemory.promptBlock()` 进了 system prompt（`lib/search/agent_service.dart:91`），再加一个工具是重复的上下文，只会挤占预算。

**不做 `list_chapters`**：章节地图（含每章 gist）已经在 `BookContext.brief` 里，`book_context.dart:118` 那段就是它。但地图有 40 章上限（`maxGists = 40`），大书要按 §8.5 加标题-only 扩写，否则"先按蒸馏定位章节"这条提示词就是空话。

### 工具返回值（喂回模型的形式）

```json
{"query":"雨","chapter":null,"hits":[
  {"chapter":7,"title":"第七章 雨夜","offset":3120,"score":9,"text":"……"},
  {"chapter":12,"title":"第十二章 归途","offset":880,"score":6,"text":"……"}
]}
```

- 每段 `text` 截到 400 字（`search_in_book`）/ 2000 字（`get_chapter`）。
- 无命中返回 `{"hits":[]}`，不带任何解释性文案——解释是模型的事。
- 执行抛错时返回 `{"error":"..."}`，让模型自己决定换参数还是放弃，**不终止这一轮**。
- PDF / 漫画这类 `chapters.contentText` 为空的书写入时，`search_in_book` 直接返回 `{"error":"这本书没有可检索的正文"}`，且分支在进入循环前就判掉（见 §10）。

## 8. 循环、上限与过程可见性

### 8.1 循环（`lib/search/tool_agent.dart`）

```
run(question, history, context, memory, hits, cancel, deadline):
  1. 组装 system（brief + memory + 规则 + 工具说明，**不含【原文片段】**）+ history + user
  2. 若 deadline 已过 → 跳到 7
  3. turn = completeTurn(messages, tools: specs, maxTokens: 500)   // 非流式
  4. 若 turn.toolCalls 为空 → 把 turn.content 作为答案首段，接上 streamChat 流式续写，结束
  5. 否则：逐个执行 toolCalls（见 8.2）→ 上报 onStep → 追加一条 assistant(tool_calls)
     以及**每个 id 对应的一条 tool 消息**（顺序与 toolCalls 一致）
  6. 回到 2，直到触顶
  7. 触顶/超时：发一次**不带 tools**的请求，附「已达到检索上限，请基于已有材料作答」，流式出答案
```

硬上限：

| 项 | 值 | 理由 |
|---|---|---|
| 工具调用次数 | 4（**以 tool_call 为单位，一个响应带 3 个就吃掉 3 次**） | 每次回 3 段 × 400 字，超过就挤掉 brief |
| 工具输出总预算 | 6000 字 | 与 `maxBriefChars` 同量级，别让检索吃掉地图 |
| 相同参数重复调用 | 第 2 次直接判触顶 | 防死循环，比步数上限更早生效 |
| 决策轮 `max_tokens` | 500 | 决策轮只输出工具调用或一句话，不需要长 |
| **墙钟总预算** | 90s（工具阶段），从第 1 次决策请求开始计 | 单轮 `requestTimeout` 已是 30s，4 轮 + 检索可能到分钟级；触顶走 7 的收尾而不是报错 |
| `CancelToken` 检查点 | 每轮开头 + 每次工具执行前 + 收尾请求前 | 「停止」要立刻生效 |

**协议有效性（最要紧的一条）**：只要发出了一条带 `tool_calls` 的 assistant 消息，下一轮请求里**每个 `toolCall.id` 都必须有对应的 `tool` 消息**。所以预算触顶、重复参数、工具抛错、deadline 到期这四种情况下，仍然是先补齐全部 `tool` 消息（内容为 `{"error":"skipped: <原因>"}`），再决定是继续还是走收尾。少一条就是静默 400。

### 8.2 一次响应多个 `tool_calls`

- 全部执行，顺序按响应里的顺序；每个都上报一个 `SearchStep`，都计入步数。
- 若执行到第 k 个时步数上限已耗尽，剩下的仍要回 `tool` 消息（`{"error":"skipped: step_limit"}`），只是不再执行、不再上报。
- 不为 `parallel_tool_calls` 发请求字段，也不依赖它：端点愿意并行就并行，串行执行也正确。

### 8.3 决策轮接口（`LlmClient` 新增，不改旧的）

```dart
class LlmToolCall {
  final String id;          // 端点给的 id，回填时必须原样带回
  final String name;
  final String arguments;   // 原始 JSON 字符串
}

class LlmTurn {
  final String content;              // 可能为空
  final List<LlmToolCall> toolCalls; // 空 = 模型要直接回答
}

// LlmClient 新增 —— 抽象类里给默认实现，避免 6 个测试假实现编译失败
Future<LlmTurn> completeTurn(
  List<LlmMessage> messages, {
  List<LlmToolSpec>? tools,
  double? temperature,
  int? maxTokens,
  CancelToken? cancel,
}) => throw UnsupportedError('completeTurn not implemented');
```

`LlmMessage` 加三个可选字段（保持位置构造器不变，调用方零改动）：

- `LlmRole.tool`（新枚举值，`toJson` 出 `"role":"tool"`）
- `toolCallId`（tool 消息回填用）
- `toolCalls`（assistant 消息回带 `tool_calls` 用）

请求体只在 `tools != null` 时加 `"tools": [...]` 和 `"tool_choice": "auto"`；`streamChat` 的实现一个字不改。

### 8.4 过程可见

`SearchStep`（内存态 + 落库）：

```dart
class SearchStep {
  final String tool;            // 'search_in_book' | 'get_chapter'
  final String summary;         // '「雨」· 全书 · 3 段' / '第 7 章 前 2000 字'
  final List<int> chapters;     // 命中的章号（1 起），get_chapter 就是它自己
  final int hits;
  final int ms;
}
```

界面（助手气泡上方）：

- 运行中：一行带脉搏动画的文字，如「翻到第 7 章…」，每来一个 step 就地更新为下一句。
- 结束：折叠成一行「检索 3 次 · 第 3、7、12 章」，可展开看每一步（工具、参数、命中数、耗时）。
- 重开历史会话：从 `stepsJson` 还原成同样的折叠行。

### 8.5 大书的章节地图

`maxGists = 40` + `maxBriefChars = 2400` 意味着 200 章的书只能看见前 40 章标题，"先按蒸馏定位再填 chapter"就断了。

- 工具路径把 brief 预算提到 **3600 字**（独立于经典路径，不动 `BookContextBuilder` 的既有行为）。
- 超 40 章时，40 章之后**只给标题不带 gist**（每章约 12 字，上限追加 200 条），前缀一句「其余章节（仅标题）」，明确告诉模型这些没有摘要、要用 `search_in_book` 去探。
- 仍然超限就截断并在 map 末尾标「（共 N 章，此处只列 M 章）」，让模型知道地图不全而不是以为书只有这么点。

## 9. 数据模型（Drift 12 → 13）

```dart
// ChatMessages 新增一列
TextColumn get stepsJson => text().nullable()();   // List<SearchStep> 或 notice 条目的 JSON
```

- `onUpgrade` 里 `if (from < 13) await m.addColumn(chatMessages, chatMessages.stepsJson);`
- 只存 `{tool, summary, chapters, hits, ms}`；**不存原文**。
- **notice 也存这里**：降级提示写成 `[{"notice":"当前模型不支持工具检索，已用摘要回答"}]`，与 step 共用一条 JSON 列，重开历史会话时灰字还在——否则目标 2 承诺的"可复盘"就只剩一半。
- 写入时机：每个 step 完成后写一次（步数 ≤ 4，不需要节流）；整轮结束时不重写。
- 中止/中断的轮次：已完成的 step 保留（`stepsJson` 有值、`status = 'interrupted'`），与现在的半截内容一致。

## 10. 服务层与接线

- 新增 `SearchToolAgent`（`lib/search/tool_agent.dart`），构造注入 `LlmClient`、`BookToolbox`。
- `SearchAgentService` **保留不动**，作为降级路径与"未绑书"路径。
- `chat_controller._stream()`（`lib/features/search/chat_controller.dart:294`）的**分支要放在构建上下文之前**：

```
可用工具路径 = bookId != null
            && 工具开关打开
            && 该书有可检索正文（chapters.contentText 非空）
            && settings['search.toolsUnsupported.<model>'] != true
```

**工具路径不带预检索片段**。这是有意的：`_formatBook`（`agent_service.dart:114`）会无条件贴【原文片段】，而 `_excerpts()` 只在 `distilled` 时才非空。工具路径用 `question: ''` 构建上下文（`excerpts == []`），或给 builder 加显式的 `includeExcerpts: false`；后一种更清楚，采用后者。否则模型可能靠那两段直接答完、一次工具都不调，§2.3 的前后对比就成了假证据。

- 未绑书 / 无正文 / 开关关 / 已标记不支持 → 现有 `SearchAgentService`（其中"未绑书"本来就不该走书内检索）。
- `SearchToolAgent` 通过回调把文本 delta 和 `SearchStep` 交给 controller；delta 仍用现有节流写库（`flush`），step 走单独的 `updateSteps`。
- 降级判定与记忆：
  - **触发条件**：`LlmException` 的 `statusCode` 为 400 / 404 / 422 / 500，且消息体片段（`_snippet`）里含 `tool` 或 `function` 之一。只此一种。
  - **不做**的判定：200 但没吐 `tool_calls`。这跟"模型觉得不必检索"无法区分，误判会把好模型永久关掉。
  - 触发后：本轮回落到 `SearchAgentService`，写 notice，并置 `search.toolsUnsupported.<model> = true`。
  - **清理由用户掌握**：设置页给出开关，关掉即恢复，也是复现"工具前"对比的唯一手段。不做自动过期。
- **总开关 `search.toolsEnabled`，默认 `true`**（用户已定：绑着书就进 agent 模式，慢可以自己关）。开关只影响 §10 的分支判定，不卸载工具代码；关掉后行为与今天完全一致（含预检索片段）。设置页放在 LLM 那一组下面，文案写「书内检索工具（多一次请求）」，并把当前模型的 `toolsUnsupported` 状态显示出来——用户看得见它为什么自己关了。
- 提示词：`searchSystemPrompt` 之后追加一段规则——先读【蒸馏】定位章节 → 需要原文证据时调 `search_in_book` → 引用写成 `> ` 块并标 `（第 N 章）` → 找不到就说「这本书里没有写到」，不许编。

## 11. 检索实现（`lib/search/book_searcher.dart`）

两阶段，先便宜后贵：

1. **章级粗排**：用 query 的 bigram 跟「章节标题 + gist」打分，取前 8 章；`chapter` 参数给了就只用那一章。
2. **段级精排**：把这 8 章正文按 200 字窗口 / 100 字步长切片，bigram 重合度 + 完整 query 子串命中加成排序，取 top `limit`。
3. 返回章号、章内字符偏移（窗口起点）、分数、片段。

- `_bigrams` 现在是 `BookContextBuilder` 的私有 static（`book_context.dart:188`），**提取为公开纯函数**放进 `book_searcher.dart`，builder 改为引用它——避免复制一份打分逻辑漂移。
- 章正文用一次性 LRU（容量 8）缓存，避免一次检索反复读库。
- 上限：单次最多扫 8 章 / 40 万字；超出的书在返回值里带 `{"truncated": true}`，提示词要求模型说"只查了一部分"。
- 纯函数 + 注入 loader，可单测。

## 12. 测试

- 单元：
  - `completeTurn` 请求体（有/无 tools、`tool_choice`）；响应解析（content 空 + 多 tool_calls、纯 content、malformed、arguments 不是合法 JSON）；`LlmMessage` 的 `tool` 角色与 `tool_calls` 序列化。
  - `BookSearcher`：命中排序、`chapter` 限定、窗口偏移正确、1 基↔0 基转换、超限 `truncated`、无命中返回空。
  - `SearchToolAgent`：脚本化假 client（①调 search_in_book ②出答案）；**一个响应带 2 个 tool_calls → 2 条 tool 消息 + 计 2 步**；相同参数第二次即触顶；步数上限后仍为每个 id 回 tool 消息（断言消息序列合法）；工具抛错变 `{"error"}`；deadline 到期走收尾；cancel 时立刻停。
  - 降级：假 client 抛 `LlmException(statusCode: 400, message 含 'tools')` → 回落 `SearchAgentService`、写 notice、置 `toolsUnsupported`；200 无 tool_calls → **不**降级。
  - 上下文：工具路径的 system prompt 不含 `【原文片段】`，经典路径仍含。
  - 迁移 12 → 13，`stepsJson` 列存在且旧行读得出。
- Widget：step 行（运行中 / 折叠 / 展开 / 从 `stepsJson` 还原）；notice 灰字重开后仍在；设置页开关。
- 回归：608 个测试全绿，`flutter analyze` 干净。
- 手工验收（写进 README）：
  - 用一本已蒸馏的书问「这本书里反复出现的雨意味着什么」——开关开：出现步骤行、命中全书检索；开关关：只有摘要。**同一本书、同一个问题、只翻一个开关**。
  - 问「第三章那个老人说了什么」——应直接 `get_chapter(3)`，不搜全书。
  - 未蒸馏的书问同一问题——工具仍可用（它扫正文，不依赖 gist），粗排只能靠标题。
  - PDF / 漫画书——不进入工具路径，行为与今天一致。

## 13. 里程碑

1. **M1 客户端能力**：`LlmMessage` 工具字段 + `completeTurn`（含默认实现）+ 解析/序列化 + 单测。此时没有任何界面变化。
2. **M2 检索与工具箱**：`BookSearcher`（含 `_bigrams` 提取）+ `BookToolbox`（两个工具，含 1 基→0 基转换）+ 单测。
3. **M3 循环**：`SearchToolAgent`（多 tool_calls、协议补全、上限、deadline、触顶收尾、降级、cancel）+ 单测。
4. **M4 接线与可见性**：迁移 12→13、`_stream` 分支（在上下文构建前）、`includeExcerpts: false`、brief 3600 + 标题-only 扩写、step 行 UI、notice 落库、设置页开关、README 验收项。
5. **M5 打磨**（可选）：决策轮流式化（方案 B）、`get_chapter` 的 offset 智能跳转。

每个里程碑独立可跑、可提交；M1–M3 完成时功能仍默认关闭。

## 14. 留给实施者的决定

- 窗口大小（200/100）与 bigram 打分的权重，按实测调。
- 决策轮 `max_tokens = 500` 是否够（工具参数很短，但有些端点会先输出一段说明）。
- step 行的折叠样式与文案（"翻到第 7 章…" vs "查「雨」…"）。
- 每轮检索结果拼进 tool 消息的具体排版。
- 墙钟 90s 的取值与超时后的文案。

## 15. 修订记录（builder check 回填）

- 一个响应可带多个 `tool_calls`：全执行、逐个计数、**每个 id 必回一条 tool 消息**（含被跳过的情况）→ §8.1/§8.2。
- 补墙钟预算 90s 与超时收尾 → §8.1。
- 工具路径**去掉预检索片段**，否则前后对比失真、模型可绕过工具 → §10。
- 降级触发条件收敛为 4xx/5xx + 正文含 tool/function；200 无 tool_calls 不降级 → §10。
- 降级提示与 steps 共用 `stepsJson`（notice 条目），重开后仍在 → §9。
- `completeTurn` 在抽象类给默认实现，保住 6 个测试假实现 → §5/§8.3。
- `_bigrams` 提取为公开纯函数复用，不复制打分逻辑 → §11。
- 大书章节地图：brief 3600 + 40 章后标题-only 扩写 → §8.5。
- 章号 1 基 / `ChapterRepository` 0 基的转换在工具箱内部 → §5/§12。
- 工具总开关默认开（用户 2026-11-05 拍板），并显示按模型的 `toolsUnsupported` 状态 → §10。
