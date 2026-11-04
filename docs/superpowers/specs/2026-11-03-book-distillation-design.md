# 书籍蒸馏（Book Distillation）— 设计文档

- 日期：2026-11-03
- 状态：待用户评审
- 分支：`feat/book-distillation`
- 参考：<https://github.com/kangarooking/cangjie-skill>（RIA-TV++，v2.5.0）

## 1. 意图与背景

陪读 agent 每次请求只有两种朴素上下文可选，都不够用：

- **只给当前章**：模型不知道这本书在讲什么、这一章在全书的位置、作者的立场和语气，解读容易跑偏，也接不住"这里为什么这么写"。
- **给整本书**：TXT/EPUB 动辄 20–50 万字，超出上下文且成本不可控。

所以要有一座**中间层**：把整本书蒸馏成一份**稳定、可复用、按需裁剪**的理解底座，请求时只带「底座 + 当前章」，既不丢全局，也不爆预算。

cangjie-skill 解决的正是"把书变成可调用单元"，但它的产物是**给 agent 执行任务用的能力卡**（R/I/A1/A2/E/B + 触发条件 + 压力测试）。陪读需要的是**理解这本书**：主旨、骨架、人物、概念、情绪、可聊的角度。因此本项目**借它的骨架，不搬它的产物形态**。

## 2. 目标

1. 为一本书生成可持久化的蒸馏产物：**全书总览、章节地图、概念/人物卡、情感与语气档案**。
2. 蒸馏过程**可中断、可续跑、可取消**；失败不丢已完成的部分。
3. 陪读请求时，按**确定性规则 + 预算**组装上下文：总览 + 语气 + 当前章 + 相邻章要点 + 命中卡片。
4. 用户自带 OpenAI 兼容模型（DeepSeek 等），密钥安全存储，不写死厂商。
5. 蒸馏不阻塞阅读；未配置模型时阅读器行为与现在完全一致。

## 3. 非目标（本期不做）

- 导出 cangjie 格式的 `SKILL.md` 包、压力测试、晋级门（留作后续 export）。
- 向量检索 / embedding 召回；本期用词面 + 章节邻近的确定性打分。
- **PDF v1 不支持蒸馏**：PDF 不写入 `Chapters` 表（CONTRIBUTING:22，`book_service.dart:91-99` 只对 txt/epub 建章），阅读走页码锚点，没有"章"这个蒸馏与剧透防护的单位。v1 对 PDF 显式禁用蒸馏入口并给出原因；页码化的伪章节留作 P6。
- 后台常驻：App 退出即暂停，重进可续跑。
- 多模型路由、代理、自定义 prompt 编辑器。
- 多人协作、云端同步。

## 4. 反目标（跑通也算失败）

- **蒸馏卡住阅读器**：导入、打开、翻页、标注不得因蒸馏变慢或报错。
- **产物与书内容脱节**：书文件变化（contentHash 不一致）后仍静默使用旧产物。
- **密钥明文入库**：API Key 不得写入 drift / 日志 / 崩溃信息。
- **一次失败全盘重来**：单块失败导致已完成的几十次调用作废。
- **上下文无上限**：任何路径都必须经过字符预算裁剪，不能把整本塞进 prompt。
- **虚构引用**：卡片和总览里的"书中原话"必须能对上原文；对不上就标注为概述。

## 5. 约束

- Flutter / Dart 3.13，Windows + Android；无后端，所有调用由客户端直连模型。
- 中文书优先；章节文本已落库（`Chapters.contentText`），无需重复解析文件。
- 现有 `AssistantService` 四个流式接口与 `ReadingContext` 必须保持向后兼容（现有测试不能红）。
- 新增依赖尽量少：`http`（或 `dart:io HttpClient`）、`flutter_secure_storage`。
- 成本目标：30 万字中文书 ≤ 60 次模型调用，单本蒸馏费用 ≤ 1 元（DeepSeek 计价）。
- 时长目标：30 万字书 5–15 分钟（并发 3，可后台续跑）。

## 6. 与 cangjie-skill 的映射

| cangjie 阶段 | 本项目采用 | 差异原因 |
|---|---|---|
| 阶段 0 Adler 整书理解 → `BOOK_OVERVIEW.md` | ✅ 采用，精简为结构化 JSON | 陪读最需要全局骨架 |
| 阶段 1 五路并行提取（框架/原则/案例/反例/术语） | ✅ 合并为单次"块级理解"提取（要点/实体/语气/引文） | 陪读不吃"可执行单元"，五路拆分会 5 倍成本 |
| 阶段 1.5 三重验证 | ✅ 采用其**思想**：产物必须能回溯章节、可被检索命中；不做四类分流 | 没有"独立 skill"概念，验证降级为可追溯性检查 |
| 阶段 1.6 晋级门 | ❌ 不做 | 产物不是独立 skill |
| 阶段 2 RIA++ 六段卡 | ⚠️ 只保留 R（原文出处）/ I（解释）/ A2（适用场景） | E/B 是执行步骤与边界，陪读用不上 |
| 阶段 3 Zettelkasten 互链 | ⚠️ 卡片记录 `related` 名称，供召回扩展 | 不做图数据库 |
| 阶段 4 压力测试 | ❌ 本期不做，用"检索命中率"离线评估替代 | 无 skill 触发语义 |
| 阶段 5 编译交付 | ⚠️ 只做 Markdown 导出（可选） | 不产出可安装 skill |

## 7. 方案对比

**A. 分层蒸馏包（选定）**：一次性离线蒸馏出「总览 + 章节地图 + 卡片 + 语气」，运行时按当前章与问题组装。
成本可控（map-reduce 一次），上下文稳定可解释，失败可续跑。

**B. 只做全书梗概 + 章节摘要**：调用最少。但答不了"这里为什么这么写""这个人物为什么这样做"，情感色彩只剩一句空话。放弃。

**C. 照搬 cangjie 全流程 skill 化**：产物漂亮、可导出生态。但能力卡面向"执行任务"，陪读需要"理解文本"；三重验证 + 晋级 + 压力测试让成本涨 3–5 倍，收益与陪读无关。放弃，只借骨架。

**选定 A**。理由：陪读的质量瓶颈是"全局理解 + 局部细节"的配比，A 正好把两者分层，且每层都可单测、可观测、可裁剪。

## 8. 蒸馏产物规格

全部以结构化 JSON 落库，UI 渲染为 Markdown 风格文本。

### 8.1 全书总览（`overview`，全局唯一，1200–2000 字）

```json
{
  "oneLiner": "一句话：这本书在回答什么问题",
  "themes": ["核心命题 1", "核心命题 2"],
  "structure": [{"part": "第一部分 认知", "chapters": "1-5", "summary": "这部分在讲什么"}],
  "argument": "作者的核心论证链条（3-5 句）",
  "stance": "作者立场、预设立场、反对什么",
  "audience": "这本书写给谁，需要什么前置知识",
  "misreadings": ["常见误读 1"],
  "conversationAngles": ["可以和读者聊的角度 1"]
}
```

### 8.2 章节地图（`chapter_gist`，每章一条，≤60 字）

```json
{"chapterIndex": 12, "gist": "本章发生了什么 / 作者想说明什么", "keyTerms": ["术语"]}
```

按"部分"批量生成（每批 6–10 章），减少调用次数。

### 8.3 概念/人物卡（`card`，24–40 张，每张 ≤200 字）

```json
{
  "slug": "kebab-id",
  "type": "concept | person | claim | method",
  "title": "认知失调",
  "summary": "一句话定义",
  "explain": "展开解释（I）",
  "apply": "在阅读/生活里怎么用（A2）",
  "sourceChapters": [3, 4],
  "quote": "书中原话（可选，≤100 字，必须能在原文定位）",
  "related": ["相邻概念 slug 或标题"]
}
```

### 8.4 情感与语气档案（`tone`，全局唯一，≤400 字）

```json
{
  "overall": "整体基调，如：冷峻、克制、带讽刺",
  "arc": [{"part": "第一部分", "mood": "焦虑 → 清醒"}],
  "narrator": "叙述视角与人称",
  "style": ["短句、大量比喻", "反讽"],
  "sampleQuotes": ["能代表语气的短句"]
}
```

`sampleQuotes` 必须来自原文（蒸馏时校验子串存在），否则丢弃。

## 9. 蒸馏流水线

```
plan     → 切块（章内切 6000 字块，段落边界；块绝不跨章）
map      → 每块一次调用：要点 / 实体 / 语气线索 / 可引用句   [可并行 3，落库]
reduce-1 → 每个"部分"（6–10 章）→ 部分摘要 + 各章 gist
reduce-2 → 全书总览 + 情感语气档案（输入：部分摘要 + 元信息）
cards    → 候选实体去重 → 分批生成概念/人物卡
verify   → 引文回查原文；卡片 sourceChapters 校验；失败项降级（去引文/标注概述）
done     → 写入 artifacts，标记 job done
```

- **断点续跑**：每个 map/reduce 单元完成即写 `DistillUnits`；`DistillJobs.stage + doneUnits` 决定从哪继续。App 重启后进入蒸馏页可"继续"。
- **幂等**：同一 `(bookId, contentHash)` 重复启动只补缺失单元。
- **失效**：`contentHash` 变化或章节重导入 → 旧产物标记 `stale`，提示重新蒸馏，不静默复用。
- **取消**：置 job 为 canceled，保留已完成单元。
- **并发**：map 阶段并发 3；失败单元重试 1 次（带 JSON 修复提示），仍失败则 job `paused` 并记录错误，可重试。

**单元定义（定稿）**

- 基准单位是 **蒸馏段** `segment`：优先取阅读章节；一章超过 6000 字则章内切段（段落边界），整本只有一章（`detectTxtChapters` 兜底「正文」）时按 6000 字切虚拟段。因此"章节"与"单元"不一一对应。
- 每个 segment 记录 `(segmentKey, readerChapterIndex, chapterTitle, charStart, charEnd)`；`unitKey = seg-0007` 之类的段序号，**不是** `chapter-0021-c01`，因为章内可能零段或多段。
- 块绝不跨章：跨章合并会让引文校验和 `sourceChapters` 归因失真，代价是"章节→块"的调用数不可压缩（见"调用预算"）。
- "部分"（reduce-1 批次）= 按**字符预算**分组，目标单批输入 ≤ 60k 字、且至少 2 章；章多字少时按 6–12 章一批。`part-02` 是批次号，不是章节区间。
- 章节地图按 **readerChapterIndex** 聚合（一个阅读章节的多个段 gist 合并成一条），`sourceChapters` 也存 reader 章节号，保证和阅读器/进度锚点对得上。


## 10. 运行时上下文组装

请求时（陪读对话 / 章节总结）由 `DistilledContextAssembler` 纯函数产出，输入 `AssembleInput{bookId, bookTitle, author, chapterIndex, chapterTitle, chapterText, chapterCharOffset, question, artifacts}`，输出 `AssembledContext{brief, spoilerGuard, tokensHint}`。

`ReadingContext` **只做追加式扩展**（可选字段，默认空，不破坏现有构造与测试）：

```dart
ReadingContext({bookTitle, author, chapterTitle, chapterText, selectedText,
  this.bookId, this.chapterIndex, this.chapterCharOffset, this.bookBrief});
```

`DigestAwareAssistantService` 负责把 `bookBrief` 填进去；`OpenAiCompatibleAssistantService` 的 prompt 组装器在有 `bookBrief` 时前置注入。接口签名 `translate/explain/summarizeChapter/chat` 一个字都不改。


| 段落 | 预算（字符） | 规则 |
|---|---|---|
| 全书总览（紧凑版） | 1200 | oneLiner + themes + structure + argument |
| 情感与语气 | 300 | overall + arc 摘要 |
| 当前章窗口 | 4000（可配） | 以阅读位置为中心开窗：章首 800 + 锚点前后 2400 + 章尾 800；锚点缺失时退化为章首 4000 |
| 前一章 / 后一章 gist | 各 60 | 章节地图命中 |
| 卡片 top-K | 3 张 × 250 | 打分后取阈值以上 |

**卡片打分（确定性）**：
`score = 3 × 术语词面重叠 + 2 × 章节区间包含当前章 + 1 × 与用户问题的字符二元组重叠`；同分按 `sourceChapters` 靠前者优先，再按 slug 字典序，保证可复现。

**降级**：无蒸馏产物 → 退回现有 `ReadingContextBuilder` 行为；蒸馏未完成 → 用已完成部分；预算超限 → 按上表优先级从低到高截断（先丢远端卡片，再丢相邻章 gist）。

**不剧透**：system prompt 里注入"读者当前位置 = 第 N 章"，要求不引用其后章节内容。

## 11. 数据模型（drift 新增表）

```
DistillJobs
  id, bookId, contentHash, status(pending|running|paused|done|failed|canceled|stale),
  stage(plan|map|reduce1|reduce2|cards|verify|done),
  pipelineVersion,            # 切块/提示词版本；变更即让旧产物失效
  totalUnits, doneUnits, errorText, createdAt, updatedAt

DistillUnits            # 断点续跑与审计
  id, jobId, unitKey(chunk-0007|part-02|overview|cards-01), kind(chunk|part|overview|cards|tone),
  status(pending|running|done|failed), resultJson, attempts, updatedAt

DistillArtifacts        # 运行时消费
  id, bookId, kind(overview|tone|chapter_gist|card), unitKey, title, body(markdown),
  dataJson, chapterStart, chapterEnd, stale, createdAt
```

索引：`DistillUnits(jobId, unitKey)` 唯一；`DistillArtifacts(bookId, kind)`；`DistillJobs(bookId)`。
删除书时级联删除 job/units/artifacts（`BookService.deleteBook` 扩展）。

## 12. 模型接入

```dart
abstract class LlmClient {
  Stream<String> streamChat(List<LlmMessage> messages);          // 陪读对话
  Future<String> completeJson(List<LlmMessage> messages, {        // 蒸馏
    String? schemaHint, int? maxTokens, double? temperature,
  });
}
```

- `OpenAiCompatibleLlmClient`：POST `{baseUrl}/chat/completions`，SSE 流式解析，非流式用于 JSON。
- 设置项（`Settings` 表 + `flutter_secure_storage`）：
  - `llm.baseUrl`（默认 `https://api.deepseek.com/v1`）
  - `llm.model`（默认 `deepseek-chat`）
  - `llm.apiKey`（仅 secure storage，永不入 DB）
  - `llm.temperature`（默认 0.3）、`llm.maxChunkChars`（默认 6000）
- 设置页提供"测试连接"按钮，失败给出可读错误（401/网络/模型不存在）。
- `assistantServiceProvider` 组合两层：`DigestAwareAssistantService(inner: 已配置 ? OpenAiCompatibleAssistantService : UnconfiguredAssistantService)`。外层只做"加载产物 + 组装 brief + 转发"，因此 assistant 层不依赖仓储，四个接口签名保持不变。

## 13. UI

- **书架卡片菜单**：新增"蒸馏"（进行中显示进度徽标；已完成显示 ✓）。
- **蒸馏页**（`features/distill/distill_page.dart`）：阶段进度（拆块 1/47 → 理解 12/47 → 汇总 → 卡片）、当前状态、暂停/继续/取消、错误信息；完成后四个 Tab：总览 / 章节地图 / 卡片 / 语气。
- **阅读页**：AppBar 增加"陪读"入口 → 底部面板 `CompanionPanel`：显示当前章标题，消息流，输入框；未配置模型时提示去设置。
- **设置页**（`features/settings/settings_page.dart`）：模型配置 + 上下文预算 + "重新蒸馏"。
- 所有蒸馏相关 UI 在无产物/未配置时静默降级，不阻断阅读。

## 14. 错误与边界

| 场景 | 行为 |
|---|---|
| 未配置 Key | 蒸馏入口提示去设置；阅读不受影响 |
| 网络断开/超时（30s） | 当前单元失败 → 重试 1 次 → job paused，保留已完成 |
| 返回非 JSON / JSON 坏 | 一次修复重试（附错误片段）；仍坏 → 该单元 failed，计入进度 |
| 书 > 100 万字 | 提示成本与时长，允许继续；分块上限保护（> 500 块拒绝） |
| PDF / 章节表为空 | 蒸馏入口禁用并说明原因（v1 不支持 PDF） |
| 整本只有一章（TXT 兜底「正文」） | 用蒸馏段（每段 ≤6000 字）替代章节单位，仍可蒸馏 |
| 引文定位失败 | 丢弃 quote，卡片保留 |
| 书被删除/换文件 | 级联删除；hash 不符标记 stale |
| App 中途退出 | job 停在 running，下次进入检测并改为 paused，可继续 |

## 15. 测试策略

- **纯函数单测**：`DistillPlanner`（切块边界、超长章、空章）、`DistilledContextAssembler`（预算、优先级、打分、降级）、`QuoteVerifier`、SSE 解析、JSON 容错。
- **流水线端到端**：`FakeLlmClient` 按 prompt 关键字返回固定 JSON，跑完整本书，断言产物数量、断点续跑、取消、单元失败后恢复。
- **仓储测试**：drift 内存库，级联删除、stale 标记、唯一键。
- **Widget 测试**：蒸馏页各状态（无 key / 进行中 / paused / done）、陪读面板未配置提示、设置页保存。
- **手动验收（Windows）**：真实 DeepSeek key 蒸馏一本 10 万字中文书，检查总览质量、章节地图准确性、陪读回答是否引用全局信息。

现有测试（`flutter test`，22 个文件 / 128 用例）必须全绿；`flutter analyze` 无新增告警。基线以命令输出为准，不引用文件数。

## 16. 里程碑（每个里程碑单独提交）

| 里程碑 | 内容 | 验收 |
|---|---|---|
| P1 | `LlmClient` + OpenAI 兼容实现 + 设置页 + 密钥存储 | 填入 Key 可测试连接；错误可读；现有测试绿 |
| P2 | 蒸馏领域层：切块、prompt、map/reduce、卡片、验证、drift 表、断点续跑 | Fake client 跑完整本书；断点/取消/失败恢复测试通过 |
| P3 | 蒸馏 UI + 产物浏览 + 书架入口 | Windows 上可见进度、可浏览四类产物 |
| P4 | 上下文组装 + 陪读面板 + 真实模型接入 | 未配置时降级；配置后回答引用总览信息 |
| P5 | Markdown 导出、stale 重蒸、打磨与文档 | 导出可读；换书文件后提示重蒸 |

## 17. 留给实施者的判断

- 用 `http` 包还是 `dart:io HttpClient`（倾向 `http`，SSE 解析更简单）。
- 卡片生成用一次大调用还是按部分分批（按 token 实测决定，分批更稳）。
- 章节地图是否缓存进 `Chapters` 表（倾向独立表，避免污染阅读数据）。
- 陪读面板是 bottom sheet 还是独立页（倾向 bottom sheet，保留阅读位置）。

## 18. 已确认决定

- 蒸馏产物服务于 **App 内陪读**，不是导出给外部 agent 的 skill 包。
- 上下文 = 蒸馏底座 + 当前章，不塞整本书。
- 蒸馏必须包含**书籍梗概、在讲什么、情感色彩**三件事（用户原话）。
- 借 cangjie 的骨架（Adler 总览、并行提取、可追溯），不搬能力卡与压力测试。

## 19. 决策记录（builder check 之后定稿）

对十个问题的最终处理，均为我的判断，实施时不再回头讨论：

1. **PDF 支持？→ v1 不做。** 理由：没有章节表就没有"章"这个单位，剧透防护、相邻章 gist、章节地图全部失效。PDF 入口禁用并说明；P6 才考虑页码伪章节（pdfrx 文本层 + 固定窗口）。
2. **单章书怎么办？→ 引入蒸馏段。** 章节 > 6000 字或整本兜底单章时，按段落边界切虚拟段（≤6000 字），段记录所属阅读章节区间；聚合粒度仍是阅读章节，另存 `readerChapterIndex`。
3. **块跨章？→ 不跨。** 块边界 = 章边界优先；`unitKey` 用 `seg-NNNN`，`sourceChapters` 存阅读章节号。代价：调用数不可压，接受。
4. **兼容怎么定义？→ 追加可选字段即可。** 四接口签名不变；`ReadingContext` 加 `bookId/chapterIndex/chapterCharOffset/bookBrief`（可选）；组装在 `DigestAwareAssistantService` 装饰层，assistant 层不碰仓储。
5. **当前章取开头还是开窗？→ 开窗。** 锚点来自阅读进度（章内字符偏移），窗口 = 首 800 + 锚点前后 2400 + 尾 800；无锚点退化章首 4000。剧透防护用 `chapterIndex`，不用"第几章"文字猜测。
6. **后台续跑？→ keepAlive Notifier 持 job 循环。** 离开蒸馏页继续跑；App 进 paused 时暂停；取消会 `LlmClient.cancel()` 中止在途流；恢复需用户点"继续"。"不阻塞阅读"由 widget test（fake client 跑 20s，同时能翻章）验证。
7. **P4 范围？→ 陪读对话 + 章节总结。** `translate/explain` 仍无 UI（记为后续），不为它们造入口。
8. **stale 触发？→ 蒸馏启动时重算 hash + `pipelineVersion`。** 重算 book 文件 SHA-256 与 job 记录比对；`pipelineVersion` 变更即让产物失效。不做文件监听、不做静默修复。
9. **调用预算硬性？→ 软目标 ≤80 次/本。** 60 次在"块不跨章 + 卡片分批"下不现实；e2e fake client 断言调用次数 ≤80，真实花费在 Windows 验收里记录。单本成本目标改为"≤2 元"。
10. **聊天历史持久化？→ v1 仅内存，按面板会话。** 不建表；避免在陪读体验定型前锁死数据模型。

顺带修掉 spec 里与当前 checkout 不符的表述：不存在的 `features/settings/settings_page.dart`、划词 AI 入口、以及"41 个测试文件"的旧基线；设置页在 P1 新建，作为本功能的依赖而非既有设施。

## 20. 实施结果（完工记录）

按计划 12 个任务全部落地，分支 `feat/book-distillation`，184 个测试全绿、`flutter analyze` 干净。与设计稿的差异只有下面这些，均已随代码提交：

1. **stale 的实际语义**：`DistillStaleGuard`（`lib/distill/stale_guard.dart`）在 `DistillController.start()/resume()` 里、真正发起模型调用前重算书籍文件 SHA-256。变化时把该书的产物全部标 `stale`、刷新 `Books.contentHash`，然后按新内容直接重跑；界面显示一句非致命的 `DistillState.notice`「书籍内容已变化，已按新内容重新蒸馏」，而不是中止等用户确认——否则用户没有任何出口能重新开始。文件缺失或读不出来时视为未变化，不误伤。
2. **暂停=取消在途单元**：`pause()` 只是置标志，`onProgress` 里检测到就把 `CancelToken` 取消；流水线以 `canceled` 收尾后，控制器把它改回 `paused` 再存库，这样"暂停"和"取消"共用一个出口，区别只在最后写回的状态。
3. **`LlmClient.streamChat` 多了可选 `cancel` 参数**（计划里没有）：没有它无法在暂停/取消时中止在途 HTTP 流。
4. **蒸馏页不依赖仓储**：`DistillView` 是纯展示组件（state + artifacts + 四个回调），`DistillPage` 才接 provider；测试可以完全绕开数据库。
5. **陪读面板的判断依据是 `AssistantService.isConfigured`**，而不是 `assistantServiceProvider` 是不是 `AsyncLoading`：面板在 loading 时显示转圈，未配置时给「去设置」入口。
6. **PDF 入口**：书架卡片的「蒸馏」菜单项对 PDF 直接 `enabled: false`（PDF 无章节表，见第 19 节第 1 条）。
7. **卡片与章节摘要不再另建表**：两者都是 `DistillArtifacts` 的行（`kind=card` / `kind=chapterGist`），`chapterStart/chapterEnd` 记录覆盖的阅读章节区间，`stale` 标记失效。
8. **调用预算没有做成硬断言**：e2e 用 fake client 断言"每个单元恰好一次调用"，真实次数与花费留给 Windows 手动验收（见 CONTRIBUTING 手动验收清单第 12–14 条）。

