# 参与贡献

这是一个**本地优先**的阅读器，目标平台是 Windows 和 Android。它首先要把阅读体验做扎实，其次作为后续 **AI 陪读 / agent** 能力的载体。当前完成的是 **Phase 1：TXT / EPUB / PDF 阅读与书签**。

- 仓库：<https://github.com/icetea718/hackathon_reading>
- 设计文档：[docs/superpowers/specs/2026-11-03-reader-app-design.md](docs/superpowers/specs/2026-11-03-reader-app-design.md)
- Phase 1 实施计划：[docs/superpowers/plans/2026-11-03-reader-phase1.md](docs/superpowers/plans/2026-11-03-reader-phase1.md)

## 当前进度

已完成：

- 书架：导入、展示、删除书籍，本地保存副本。
- TXT 编码识别：UTF-8（含 BOM）、UTF-16 LE/BE（含 BOM）、GB18030/GBK/GB2312，严格解码失败时降级而不崩溃。
- 章节识别：行首标题规则（`第X章/节/卷/回/部/篇/集`、序章、楔子、前言、番外、`Chapter N` 等）；无标题时整本书作为一章。
- EPUB 解析：EPUB3 nav / EPUB2 NCX 目录、spine 顺序、纯文本提取、统一字符偏移；损坏文件干净失败。
- 阅读器：目录抽屉、上一章/下一章、字号与行距调整、三种背景色。
- 书签：当前章节添加/取消，抽屉“书签”栏跳转和删除。
- 阅读进度：以全书字符偏移为锚点，滚动防抖保存，重新打开回到原位置；调整字号或窗口大小不丢位置。
- 正文按章节懒加载。
- PDF 阅读：pdfrx 渲染、缩放、翻页/页码跳转、内嵌目录（无目录时按页跳转）、按页码续读；PDF 不写入章节表。
- 重复导入保护：按文件内容 SHA-256 去重，旧书在首次导入时自动补算哈希。
- 94 个自动化测试；Windows 构建与启动、Android debug APK 构建均已验证。

尚未实现：PDF 标注/高亮、EPUB 排版还原（CSS/图片/封面）、TXT/EPUB 之外的高亮/笔记、阅读设置持久化、任何 AI 调用。扫描版 PDF 不做 OCR。

## 产品方向

做这个项目时请守住两条线：

1. **阅读器先可靠。** 导入、章节、目录、续读、标注这些基础能力优先于 AI 功能。
2. **AI 能力只通过预留接口接入。** UI 不直接依赖数据库或模型厂商；后续所有 AI 调用都走 `AssistantService`（见设计文档第 11 节）。第一版接口用 `Stream` 定义，未配置时返回明确的“未配置”提示，不能影响阅读。

MVP 的非目标：账号体系、云同步、书架社区、复杂排版引擎、OCR。

## 技术栈

| 层 | 选型 |
| --- | --- |
| UI / 业务 | Flutter 3.47（Dart 3.13）、flutter_riverpod 3.x |
| 本地存储 | Drift（SQLite）+ drift_flutter |
| 文件选择 | file_picker |
| 中文编码 | chinese_codec（GB18030/GBK/GB2312） |
| EPUB 解析 | archive + xml（纯 Dart，自行解析 OPF/nav/NCX） |
| PDF 渲染 | pdfrx（PDFium 原生库由构建钩子下载） |
| 平台 | Windows、Android |

## 目录结构

```text
lib/
  app/                 入口、主题、全局 provider
  data/
    db/                Drift 表结构与数据库（含生成的 app_database.g.dart）
    repositories/      书籍、章节、阅读进度、标注、设置仓储
    storage/           书籍副本等文件存储
  domain/
    models/            Book、Chapter、ReadingProgress 等模型
    services/         导入、编码识别、章节识别等纯逻辑
  features/
    library/           书架、导入、删除
    reader/            阅读视图、目录、设置、进度定位
```

标注的模型、表和仓储已经存在（当前用于书签），但 UI 仍放在 `features/reader`；`assistant/` 目录还没有，是设计文档中后续里程碑的位置。新增功能时请按“UI / domain / data”分层，不要把这些逻辑直接塞进 `features/reader`。

## 环境准备

通用要求：Flutter 3.47.x、`flutter pub get`。中国大陆网络可设置镜像：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

Windows：

- Visual Studio 2022，安装“使用 C++ 的桌面开发”工作负载。
- 开启 Windows 开发者模式（插件构建需要符号链接支持）。

Android：

- Android SDK：platform 36、build-tools 36.0.0、platform-tools。
- NDK 28.2.13676358（Flutter Gradle 插件强制要求该版本）。
- JDK 21。

只有修改 Drift 表结构时才需要重新生成代码：

```bash
dart run build_runner build --delete-conflicting-outputs
```

## 运行、测试与构建

```bash
flutter run -d windows
flutter analyze
flutter test
flutter build apk --debug
```

提交前**必须**保证 `flutter analyze` 无问题、`flutter test` 全绿。当前基线是 94 个测试全部通过；新增功能后数量会增长，以全绿为准。

PDF 渲染依赖 pdfrx，首次构建会从 GitHub 下载 PDFium 原生库。GitHub 不可达时构建钩子会失败；先按 README 的说明用镜像预置 `.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_8125/<平台>/` 下的原生库再构建。

## 开发流程

1. **从 `main` 切分支**，不要直接改 `main`。
   - 功能：`feat/<简短英文名>`
   - 修复：`fix/<简短英文名>`
   - 文档：`docs/<简短英文名>`
2. **先读设计文档和计划。** 与设计冲突的方案先讨论，不要默默改方向。
3. **采用 TDD。** 先写会失败的测试并确认它失败，再写最小实现，再跑全量测试。解析器、锚点计算、仓储、widget 行为都适用。
4. **小步提交。** 提交信息沿用现有风格（`feat:` / `fix:` / `docs:` / `build:` / `test:`），一个提交只做一件事。
5. **发起 Pull Request 到 `main`。** 说明改了什么、为什么、如何验证；如果改了界面，附截图或录屏。
6. **涉及风险的操作先确认**：数据库迁移、删除数据、修改 CI、改动共享配置、强制推送。

不要提交：`.claude/`、编辑器临时文件、无关的个人文本文件、构建产物、密钥或账号信息。

## 代码约定

- **分层**：`features`（UI）依赖 `domain` 的模型/服务；`data` 实现存储；UI 不直接写 Drift 查询，也不直接调用模型厂商。
- **Riverpod 3.x**：`AsyncValue.value` 可能为 `null`，不要用 `valueOrNull`；不能在 `dispose` 阶段 `ref.read`，需要在 build 时把依赖缓存到 State 字段。
- **Drift**：所有读写走 repository；改表结构时同步提高 `schemaVersion` 并写 `onUpgrade`；`app_database.g.dart` 随代码提交。
- **阅读位置**：TXT/EPUB 的锚点是**全书字符偏移**，不是滚动像素；章节内换算用 `lib/features/reader/reader_position.dart` 的 `locateAnchor` / `anchorOffsetForFraction`，注意章节首尾边界。PDF 的锚点是 1-based 页码（`ReadingAnchor.page`），不要用字符偏移。
- **懒加载**：目录只取章节元数据（`getSummariesForBook`），正文按章取（`getContent`）。不要退回到一次性加载整本书正文。
- **文案**：界面文案用中文；错误提示要可读，不要把 `error.toString()` 直接展示给用户。
- **测试**：仓储测试用内存 Drift；widget 测试里的真实文件/数据库 I/O 要放进 `tester.runAsync`；临时目录在 `setUp` 创建、`tearDown` 清理。

## 如何扩展

### 新增输入格式（例如 MOBI）

1. 在 `domain/models/book.dart` 的 `BookFormat` 中新增格式枚举和扩展名映射。
2. 在 `domain/services/` 增加解析器，输出统一的 `List<Chapter>`（标题 + 偏移 + 正文）；无法转成字符流的版式（如 PDF）则单独写阅读器，不进章节表。
3. 在 `domain/services/book_service.dart` 的导入流程中调用解析器并写入章节。
4. 更新 `features/library/book_card.dart` 的打开逻辑与 `features/reader` 的渲染方式；PDF 的现有实现可参考 `pdf_reader_page.dart` / `pdf_reader_providers.dart`。
5. 为解析器写单元测试，覆盖目录缺失、编码/结构异常、大文件；渲染层用可注入的 builder 隔离原生依赖，见 `pdfViewerBuilderProvider`。

### 新增标注 / 书签 / 高亮

1. 在 `data/db/tables.dart` 新增表，写 `schemaVersion` 迁移。
2. 新增对应的 Drift 仓储和 domain 模型。
3. 在 reader 中做选区与渲染，标注面板通过仓储读取。
4. 测试覆盖增删改、跨章节定位、删除书籍时的级联清理。

### 接入 AI 能力

严格按设计文档第 11 节：

1. 实现 `AssistantService` 的 `translate` / `explain` / `summarizeChapter` / `chat`，统一返回 `Stream`。
2. 用 `ReadingContextBuilder` 组装书名、作者、当前章节与选中文本，并做长度截断。
3. 模型厂商适配器放在 `assistant/`，API Key 走安全存储，不写进代码或日志。
4. 未配置时 UI 显示明确提示，不能阻断阅读。

## 手动验收清单

自动化测试之外，合入前建议在 Windows 或 Android 上走一遍：

1. 导入 UTF-8 中文 TXT 和 GB18030 中文 TXT，正文与目录正常。
2. 导入 EPUB，章节顺序与目录正常，正文可读。
3. 从目录跳章，上一章/下一章可用；左上角返回键能回到书架。
4. 添加/取消书签，在抽屉“书签”栏跳转和删除。
5. 滚到章节中部，关闭应用重开同一本书，回到原段落。
6. 调整字号/行距、改变窗口大小，当前位置不丢。
7. 导入带内嵌目录的 PDF，目录正确、点击跳页；翻到中间页退出重开回到原页；缩放、输入页码跳转可用。
8. 重复导入同一本书，出现「这本书已经在书架中」提示，书架不会多出一条。
9. 删除书籍后，书架条目和本地副本都消失。
10. 导入不支持格式或空文件，出现中文错误提示且书架不残留脏数据。

## 沟通

- 需求、范围、优先级以设计文档为准；改动方向先在 issue 或 PR 里讨论。
- 不确定的地方尽早提问，比做完再返工便宜。
- 评审关注点：分层是否清晰、失败路径是否可读、测试是否真的能失败、阅读位置是否稳定。
