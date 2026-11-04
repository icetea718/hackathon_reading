# 免费联网搜索源（必应 RSS）设计

日期：2026-11-04
状态：待批准
关联：`2026-11-04-search-and-read-shell-design.md`

## 1. 意图与原因

现在「联网」必须先去 Tavily 注册、填写 API Key 才能用（`SearchConfig.isConfigured` 把 `apiKey` 焊死在判断里）。这是把基础设施的复杂度转嫁给用户：想搜一次「最近 AI 有什么新闻」，得先注册一个海外账号。

要的是：**两种源并存，用户点输入框下方的「联网」时当场选**
- 原来的 Tavily（要 Key，质量高）
- 新增免费源（不要 Key、不要服务器、国内可直连）

用户已选定：免费源走**必应中国的搜索结果**（路线 A），目标是通用网页检索，不是百科问答。

## 2. 目标

- 点「联网」弹出选择面板：关闭 / 免费搜索 / Tavily；选择立即生效并持久化
- 免费源零配置可用，失败时走既有的 degraded 静默降级，不打断对话
- Tavily 原有行为、测试、配置字段完全不变

## 3. 非目标

- 不做多源聚合、不做 query fan-out、不做抓正文二跳
- 不改 prompt 结构与 `AgentService`，不改检索结果的注入方式
- 不新增任何依赖（HTTP 仍用 `dart:io`；解析复用已有的 `xml` 包）
- 不改「书架 provider」与书架搜索

## 4. 反目标

- 免费源失效导致「联网」整体不可用 —— 必须仍能切回 Tavily 或关闭
- 把两个源的配置揉进同一个字段（`apiKey` 不能被免费源复用）
- 「未配置」被静默吞掉（用户点了 Tavily 却什么都没发生）

## 5. 约束

- 设计文档 §11：不新增 HTTP 包。已确认 `pubspec.yaml` 里有 `xml: ^7.1.0`，可以解析 RSS，无需新依赖。
- 平台 Windows + Android，`dart:io` 在两端都可用。
- 既有 334 个测试必须保持全绿。

## 6. 方案（已选 A）

| 方案 | 结论 |
|---|---|
| **A. 必应中国搜索结果** | **采用**。`cn.bing.com/search?q=…&format=rss` 返回标准 RSS（已实测 HTTP 200，含 `title/link/description/pubDate`），国内直连，用现有 `xml` 解析。 |
| B. 公共 SearXNG 实例 | 放弃：多数实例禁用 `format=json`，国内可达实例稀少 |
| C. DuckDuckGo HTML | 放弃：国内不可达 |
| D. 自建代理 | 暂缓：需要服务器，用户当前没有 |

选 A 的理由：唯一同时满足「国内可访问 + 免 Key + 免服务器」的方案；RSS 是结构化的，解析成本比抓 HTML 低一个量级。

## 7. 已知风险（记录在案，不阻塞）

1. `format=rss` 是必应的未公开输出格式，随时可能失效或限流。缓解：端点抽成常量 + 解析器独立可替换；解析失败只影响免费源。
2. RSS 的 copyright 声明限定「个人非商业 RSS 聚合」用途。当前是个人项目；若对外发布，这一点要重新评估。
3. 质量短板：`q=AI news` 实测返回的多是门户首页（artificialintelligence-news.com、techcrunch.com 分类页），不是单篇新闻。snippet 里带日期，够模型说「有几家媒体在追踪」，但做不到逐条列事件。缓解：暂不缓解，写进文档；若后续要提升，走「抓正文二跳」而不是换源。
4. `pubDate` 形如 `周三, 04 11月 2026 08:39:00 GMT`，`HttpDate.parse` 不吃，需要宽松解析，解析不出来就留 null。

## 8. 设计

### 8.1 配置模型

- `SearchConfig` 增加常量 `free = 'free'`；`provider` 取值 `off | free | tavily`
- 新增 `bool get requiresApiKey => provider == tavily;`
- `isConfigured => provider != off && (!requiresApiKey || apiKey.trim().isNotEmpty)` —— 免费源不再被 Key 卡住
- `isEnabled` 保持 `=> isConfigured`
- 存储键不变（`search.provider` / `search.apiKey`），无需迁移

### 8.2 Provider 契约

`SearchProvider` 接口不改（不在接口上加 `needsApiKey`，避免波及既有 fake）。是否需要 Key 由配置层表达：`SearchConfig.requiresApiKey`。

### 8.3 免费源实现 `lib/search/free_web_search_provider.dart`

- `FreeWebSearchProvider implements SearchProvider`
  - `id = 'free'`, `needsApiKey = false`, `isConfigured = true`
  - `endpoint = 'https://cn.bing.com/search'`，参数 `q` + `format=rss`
  - 请求头：桌面 Chrome UA + `Accept-Language: zh-CN,zh;q=0.9`
  - 传输层与 Tavily 同构：可注入的 transport 函数（返回 `(status, body)`），`CancelToken` 监听 → `client.close(force: true)`，20s 超时（复用 `defaultUrlTimeout` 概念）
  - 解析：`XmlDocument.parse(body)` → 所有 `item` → `title` / `link` / `description` / `pubDate`
    - `description` 去掉内联 HTML 标签（必应会插 `<b>`）并折叠空白
    - `publishedAt` 宽松解析两种格式（中文星期月份 / RFC 1123），失败置 null
    - `source` 复用 `_hostOf`（去 `www.`）
  - `count` 默认 5，夹到 1..10（RSS 一次约 10 条）
  - 异常文案与 Tavily 保持一致：`联网搜索超时` / `网络错误：…` / `已取消` / 非 200 时 `HTTP {code}: …`
  - 解析成功但 0 条 → 返回空列表（由 controller 走既有的 degraded 路径）

### 8.4 选择面板（核心交互）

点「联网」不再直接切 bool，而是**同时承载开关与选源**——避免两份真相（现在 `_webSearch` 是 `SearchShell` 里的本地 bool，没持久化）：

- `SearchShell` 删掉 `_webSearch` 状态，`webEnabled` 一律由 `searchConfigProvider` 派生（`provider != off`）
- 新增 `lib/features/search/search_source_sheet.dart`：`showModalBottomSheet`，三个选项
  - 「关闭」——`provider = off`
  - 「免费搜索」副标题「必应网页结果 · 免 Key · 偶尔不稳定」——`provider = free`
  - 「Tavily」副标题「质量更好 · 需要 API Key」；未填 Key 时该项仍可点，选中后提示「先在设置里填 Tavily API Key」且**不**改变当前源（反目标 3）
- 选中即写库：`searchConfigStore.save` → `ref.invalidate(searchConfigProvider)`；面板关闭
- Chip 文案带上当前源：关 / 免费 / Tavily（`chat-web-toggle` 键保留，测试仍可点）

### 8.5 发送路径

- `ChatController.send(webSearch: …)` 语义不变；`SearchShell` 传 `provider != off`（免费源恒可用，Tavily 仍需 Key——由 `isConfigured` 表达）
- **顺带修掉评审里的 P0-1**：`_retry` 现在只传 `_webSearch`，绕过 Key 检查，改为与 `send` 共用同一个 `webEnabled` 取值

### 8.6 设置页

- 「搜索服务」下拉增加「免费搜索（免 Key）」
- `Tavily API Key` 输入框仅在选中 Tavily 时显示，helper 文案不变
- 「测试搜索」按当前选中的 provider 跑 `search('ping', count: 1)`

### 8.7 测试（先写断言）

- `test/search/free_web_search_provider_test.dart`（新）
  - RSS fixture → 5 条 hit，字段映射正确，`source` 为域名
  - `count: 2` 只回 2 条；`count: 99` 夹到 10
  - `description` 里的 `<b>` 与实体会被清理/解码
  - 中文 `pubDate` 解析成 UTC 时间；解析失败时 null 且不抛
  - 非 XML 响应 → `SearchException`；HTTP 500 → `HTTP 500: …`；cancel → `已取消`
  - 0 个 `item` → 空列表
- `test/search/search_config_test.dart`（新）
  - `free` 无 Key → `isConfigured` 为 true；`tavily` 无 Key → false
  - 存取往返不丢字段
- `test/features/search_shell_test.dart`（扩展）
  - 点「联网」弹出面板，含三个选项
  - 选「免费搜索」→ chip 变选中、`send` 的 `webSearch` 为 true
  - 未配 Key 选「Tavily」→ 无效果 + 提示（不进入联网态）
  - 选「关闭」→ chip 取消选中
- 回归：`flutter analyze` 0 issue、`flutter test` 全绿（≥334）

## 9. 我需要做决定的（已作为我的判断写入上面，可推翻）

- 面板把「开关」和「选源」合一，而不是保留一个独立 bool —— 因为现在的 bool 没持久化，两份状态迟早会漂
- provider 机器名用 `free` 而不是 `bing` —— 未来换成搜狗/代理时 id 不必变
- 免费源失败时不做重试、不加保底提示条 —— 沿用 §8 的 death-by-degrade 语义，用户看到的就是「本次未使用联网结果」

## 10. 留给实现者

- RSS 解析对必应改版的容错细节（缺 `item` 时返回空而非抛错）
- UA 字符串的具体取值
- 面板的视觉细节（列表密度、是否显示分隔线）
- 是否给免费源加一层进程内 LRU 缓存（评审 P2-13 提到过，本期可不做）
