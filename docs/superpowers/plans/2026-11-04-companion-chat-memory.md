# 陪读聊天记忆 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把陪读面板从会话内内存历史改为按章节持久化的多线程聊天，并让前序章节的对话纪要进入后续提问的模型上下文。

**Architecture:** Drift schema v10 新增 `companion_threads` / `companion_messages` 两张表，新增 `CompanionChatRepository` 负责线程、消息与确定性记忆纪要。面板把用户消息在请求前写入、助手消息在流完整结束后整条写入；切章递增请求令牌使旧回复不落库。历史页按章节分组管理线程，旧章节线程只读回看并通过阅读器跳到该章。助手层仍不访问数据库，记忆通过 `ReadingContext.companionMemory` 传入系统提示。

**Tech Stack:** Flutter 3.47.9 / Dart 3.13.7、Riverpod 3.x、Drift 2.35、uuid 4.x、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-04-companion-chat-memory-design.md`

## Global Constraints

- 不推送、不合并、不 force-push；除非得到用户当下明确同意。仓库有协作者，推送前先 `git fetch` 确认没有分叉。
- 不打印、不提交、不落盘任何 API Key 或令牌；本机数据库里有明文 `llm.apiKey`，永远不要复述。
- 只暂存本计划涉及的具体文件，禁止 `git add -A` / `git add .`；不要提交 `.claude/`、`.superpowers/`、`problem.txt`、`新建 文本文档.txt`、`samples/`、构建产物。
- 不要对既有文件运行 `dart format`；新文件按仓库现有风格书写。
- Flutter 不在 PATH：`F:/src/flutter/bin/flutter.bat`、`F:/src/flutter/bin/dart.bat`。测试一律 `--no-pub`。
- 每个任务结束跑一次 `F:/src/flutter/bin/flutter.bat analyze` 和 `F:/src/flutter/bin/flutter.bat test --no-pub`；全绿才提交。
- schema 当前 v9，本计划升到 v10；迁移必须可重入（先查 `sqlite_master` 再创建），`lib/data/db/app_database.g.dart` 随代码提交。
- 助手层（`lib/assistant/*`）不得读取数据库；记忆只通过 `ReadingContext.companionMemory` 进入系统提示。
- 界面文案必须逐字一致：`聊天`、`历史`、`新对话`、`当前章`、`只读`、`前往该章`、`共 N 条`、`暂无前序章节对话`、`引用之前章节的对话纪要（≤400 字），不读取后面的章节`、`保存在第 X 章，当前为只读`、`未配置 AI 服务，请到设置页填写`、`去设置`、`总结本章`。
- 当前测试基线 497；实现完成后把 README / CONTRIBUTING 里的数字改成实际全绿数量。
- 提交粒度按任务；提交信息沿用 `feat:` / `docs:` 风格。

## Review Focus

以下输入是 spec 隐含、但单看每个任务的测试容易漏掉的地方；每一条都在对应任务里加了测试：

1. 流式回复进行中切章：旧回复不得写入新章，也不得写回旧章。测试在 Task 4。
2. 删除正在生成回复的线程：先让请求失效再删除，迟到的回复不能落库。测试在 Task 5。
3. 从底部面板跳章：底部面板必须先关闭，跳章后重新打开显示目标章最近线程。测试在 Task 6。
4. 未配置模型：聊天不能发送，但已保存的历史仍可打开阅读。测试在 Task 5。
5. 0 条消息的线程：历史里显示「共 0 条」，可重命名、可删除；删除唯一线程后聊天页回到空状态。测试在 Task 5。

---

### Task 1: Schema v10 与会话模型

**Files:**
- Modify: `lib/data/db/tables.dart`（文件末尾追加两张表）
- Modify: `lib/data/db/app_database.dart`
- Modify: `lib/data/db/app_database.g.dart`（重新生成）
- Create: `lib/domain/models/companion_chat.dart`
- Modify: `test/data/migration_test.dart`
- Create: `test/domain/companion_chat_test.dart`

**Interfaces:**
- Produces:
  - Drift 表 `CompanionThreads` → SQL 表 `companion_threads`；`CompanionMessages` → `companion_messages`。
  - 索引常量 `companionThreadsBookChapter`（SQL `companion_threads_book_chapter`）、`companionMessagesThreadSeq`（SQL `companion_messages_thread_seq`，唯一）。
  - 生成的行类 `CompanionThreadRecord`、`CompanionMessageRecord`；伴随类 `CompanionThreadsCompanion`、`CompanionMessagesCompanion`。
  - `enum CompanionRole { user, assistant }`，带 `static CompanionRole fromName(String name)`（未知值回落 `user`）。
  - `class CompanionThread`：`id, bookId, chapterIndex, chapterTitle, title, createdAt, updatedAt, messageCount = 0`，`copyWith({String? title, DateTime? updatedAt, int? messageCount})`。
  - `class CompanionMessage`：`id, threadId, role, content, seq, createdAt`。
  - `String companionThreadTitle(String text)`：`trim()` 后按 Unicode 码点取前 16 个字符，超出加 `…`。

- [ ] **Step 1: 写失败的迁移测试**

把 `test/data/migration_test.dart` 中三处 `expect(db.schemaVersion, 9)` / `expect(version.read<int>('user_version'), 9)` 改成 10，并把第一个测试名改为 `upgrades a v5 database through v10`。追加两个测试：

```dart
test('upgrades a v9 database to the companion chat tables', () async {
  final db = AppDatabase(NativeDatabase.memory(
    setup: (raw) {
      raw.execute('PRAGMA user_version = 9;');
    },
  ));

  final tables = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  final names = tables.map((row) => row.read<String>('name')).toSet();
  expect(names, containsAll(['companion_threads', 'companion_messages']));

  final indexes = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
      .get();
  final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
  expect(
    indexNames,
    containsAll([
      'companion_threads_book_chapter',
      'companion_messages_thread_seq',
    ]),
  );

  final version = await db.customSelect('PRAGMA user_version').getSingle();
  expect(version.read<int>('user_version'), 10);
  await db.close();
});

test('re-running the v10 migration tolerates an existing table', () async {
  final db = AppDatabase(NativeDatabase.memory(
    setup: (raw) {
      raw.execute('PRAGMA user_version = 9;');
      raw.execute(
        'CREATE TABLE companion_threads ('
        'id TEXT NOT NULL PRIMARY KEY, '
        'book_id TEXT NOT NULL, '
        'chapter_index INTEGER NOT NULL, '
        'chapter_title TEXT NOT NULL, '
        'title TEXT NOT NULL, '
        'created_at INTEGER NOT NULL, '
        'updated_at INTEGER NOT NULL)',
      );
      raw.execute(
        'CREATE INDEX companion_threads_book_chapter '
        'ON companion_threads (book_id, chapter_index)',
      );
    },
  ));

  final tables = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  final names = tables.map((row) => row.read<String>('name')).toSet();
  expect(names, contains('companion_messages'));
  await db.close();
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/data/migration_test.dart`
Expected: FAIL —— `Expected: <10> Actual: <9>`，且缺少 `companion_threads` / `companion_messages`。

- [ ] **Step 3: 加表、迁移与生成代码**

在 `lib/data/db/tables.dart` 末尾追加：

```dart
@DataClassName('CompanionThreadRecord')
@TableIndex(
  name: 'companion_threads_book_chapter',
  columns: {#bookId, #chapterIndex},
)
class CompanionThreads extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  IntColumn get chapterIndex => integer()();
  TextColumn get chapterTitle => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CompanionMessageRecord')
@TableIndex(
  name: 'companion_messages_thread_seq',
  columns: {#threadId, #seq},
  unique: true,
)
class CompanionMessages extends Table {
  TextColumn get id => text()();
  TextColumn get threadId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  IntColumn get seq => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

在 `lib/data/db/app_database.dart`：把两张表加进 `@DriftDatabase(tables: [...])`，`schemaVersion` 改为 10，`onUpgrade` 末尾加可重入分支：

```dart
if (from < 10) {
  final tables = await m.database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  final names = tables.map((row) => row.read<String>('name')).toSet();
  if (!names.contains('companion_threads')) {
    await m.createTable(companionThreads);
  }
  if (!names.contains('companion_messages')) {
    await m.createTable(companionMessages);
  }
  final indexes = await m.database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
      .get();
  final indexNames =
      indexes.map((row) => row.read<String>('name')).toSet();
  if (!indexNames.contains('companion_threads_book_chapter')) {
    await m.create(companionThreadsBookChapter);
  }
  if (!indexNames.contains('companion_messages_thread_seq')) {
    await m.create(companionMessagesThreadSeq);
  }
}
```

Run: `F:/src/flutter/bin/dart.bat run build_runner build --delete-conflicting-outputs`
Expected: 生成成功，`lib/data/db/app_database.g.dart` 出现两张新表与两个索引常量。

- [ ] **Step 4: 运行迁移测试确认通过**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/data/migration_test.dart`
Expected: PASS（6 个测试）。

- [ ] **Step 5: 写失败的标题截断测试**

创建 `test/domain/companion_chat_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';

void main() {
  test('a short first message becomes the thread title unchanged', () {
    expect(companionThreadTitle('  福贵为什么败家？  '), '福贵为什么败家？');
  });

  test('a long first message is cut at sixteen characters', () {
    final title = companionThreadTitle('一二三四五六七八九十一二三四五六七八九十');
    expect(title, '一二三四五六七八九十一二三四五六');
    expect(title, endsWith('…'));
  });

  test('sixteen characters exactly are not cut', () {
    const text = '一二三四五六七八九十一二三四五六';
    expect(companionThreadTitle(text), text);
  });
}
```

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/domain/companion_chat_test.dart`
Expected: FAIL to compile —— `companion_chat.dart` / `companionThreadTitle` 不存在。

- [ ] **Step 6: 写模型与标题函数**

创建 `lib/domain/models/companion_chat.dart`，包含 Task 1 Interfaces 中的三个类型。标题实现用码点，避免把代理对切成半个字符：

```dart
String companionThreadTitle(String text) {
  final trimmed = text.trim();
  final runes = trimmed.runes.toList();
  if (runes.length <= 16) return trimmed;
  return '${String.fromCharCodes(runes.take(16))}…';
}
```

- [ ] **Step 7: 运行单元测试确认通过**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/domain/companion_chat_test.dart test/data/migration_test.dart`
Expected: PASS（9 个测试）。

- [ ] **Step 8: 跑全量测试并提交**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿（497 + 新增）。

```bash
git add lib/data/db/tables.dart lib/data/db/app_database.dart lib/data/db/app_database.g.dart lib/domain/models/companion_chat.dart test/data/migration_test.dart test/domain/companion_chat_test.dart
git commit -m "feat: add companion chat tables and conversation models"
```

---

### Task 2: CompanionChatRepository

**Files:**
- Create: `lib/data/repositories/companion_chat_repository.dart`
- Create: `test/data/companion_chat_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的表、行类与 `CompanionThread` / `CompanionMessage` / `CompanionRole`。
- Produces: `class CompanionChatRepository`，构造 `CompanionChatRepository(AppDatabase db, {String Function()? newId, DateTime Function()? now})`，方法：

```dart
Future<CompanionThread?> latestThreadForChapter(String bookId, int chapterIndex);
Future<CompanionThread?> threadById(String id);
Future<List<CompanionThread>> threadsForBook(String bookId);
Future<CompanionThread> createThread({
  required String bookId,
  required int chapterIndex,
  required String chapterTitle,
  String title = '新对话',
});
Future<void> renameThread(String id, String title);
Future<void> deleteThread(String id);
Future<List<CompanionMessage>> messagesForThread(String threadId);
Future<CompanionMessage> appendMessage({
  required String threadId,
  required CompanionRole role,
  required String content,
});
Future<String> memoryDigest({
  required String bookId,
  required int beforeChapterIndex,
  int maxChars = 400,
});
Future<void> deleteForBook(String bookId);
```

- 语义：`appendMessage` 在同一事务里取 `max(seq)+1`、插入消息、把线程 `updatedAt` 写成同一条消息的时间；`renameThread` 对空白标题直接返回；`memoryDigest` 只读 `chapterIndex < beforeChapterIndex` 中 `updatedAt` 最新的最多 3 条线程，每条取最后 2 条消息，每条截到 100 字（超出加 `…`），格式 `【章节名】读者：… 助手：…`，总长 ≤ `maxChars`。

- [ ] **Step 1: 写失败的仓储测试**

创建 `test/data/companion_chat_repository_test.dart`。固定时钟与 id：

```dart
late AppDatabase db;
late CompanionChatRepository repo;
late DateTime clock;
var ids = 0;

setUp(() {
  db = AppDatabase(NativeDatabase.memory());
  clock = DateTime(2026, 11, 4, 9);
  ids = 0;
  repo = CompanionChatRepository(
    db,
    newId: () => 'id-${ids++}',
    now: () => clock,
  );
});
```

包含这些测试（名称与断言）：

```dart
test('messages come back in sequence order', ...);
  // 追加 user 'q1'、assistant 'a1'、user 'q2'
  // expect contents == ['q1','a1','q2']; seq == [1,2,3]

test('latestThreadForChapter follows the most recently used thread', ...);
  // c0 = createThread(bookId:'b1', chapterIndex:1, chapterTitle:'第二章', title:'旧')
  // c1 = createThread(... title:'新')
  // clock = clock.add(1 min); appendMessage(c0, user, '刚刚又问了一句')
  // expect((await repo.latestThreadForChapter('b1', 1))!.id, c0.id)

test('threadsForBook counts messages per thread', ...);
  // 同一章先建 0 条消息的线程 A（clock），clock += 1 min
  // 再建线程 B 并追加 2 条；行按 updatedAt desc，所以 B 在前
  // rows = await repo.threadsForBook('b1')
  // expect(rows.map((t) => t.messageCount), [2, 0])

test('memory digest only includes chapters read before the current one', ...);
  // 第一章线程（2 条）、第三章线程（1 条），beforeChapterIndex: 2
  // digest contains '【第一章】'、'读者：…'、'助手：…'
  // digest isNot(contains('后面会怎样'))

test('memory digest keeps the newest three threads, oldest first', ...);
  // 4 个 chapterIndex:0 线程，标题 一/二/三/四，每线程 1 条消息，逐次推进 clock
  // digest = memoryDigest(bookId:'b1', beforeChapterIndex:1)
  // expect(digest.length, lessThanOrEqualTo(400))
  // expect(digest, isNot(contains('【一】')))
  // expect(digest.indexOf('【二】') < digest.indexOf('【四】'), isTrue)

test('memory digest keeps only the last two messages per thread', ...);
  // 同一线程 q1/a1/q2/a2；digest contains q2/a2，isNot contains q1/a1

test('a blank rename is ignored and a real one is trimmed', ...);
  // renameThread(id, '   ') → 原标题；renameThread(id, '  新标题  ') → '新标题'

test('deleting a thread deletes its messages', ...);
  // deleteThread → threadById null；messagesForThread empty

test('deleteForBook only removes that book', ...);
  // b1 两个线程、b2 一个线程；deleteForBook('b1')
  // threadsForBook('b1') empty；threadsForBook('b2') 仍有 1 条且消息仍在
```

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/data/companion_chat_repository_test.dart`
Expected: FAIL to compile —— repository 不存在。

- [ ] **Step 2: 实现 repository**

要点（实现者按此写）：

- `threadsForBook`：先按 `chapterIndex asc, updatedAt desc` 取线程行；再用一条 `selectOnly(companionMessages) + addColumns([threadId, id.count()]) + groupBy([threadId])` 取每个线程的消息数，映射进 `CompanionThread.messageCount`。
- `appendMessage` 用 `_db.transaction`；`seq` 用 `selectOnly` 的 `seq.max()`；插入后 `update(companionThreads).write(CompanionThreadsCompanion(updatedAt: Value(time)))`。
- `memoryDigest`：按 `updatedAt desc, createdAt desc` 加 `limit(3)` 选线程；每条线程按 `seq desc limit(2)` 取消息再反转；`_clip` 为 `text.length <= 100 ? text : '${text.substring(0, 100)}…'`；逐段累加 `segment.length + (已有段 ? 1 : 0)`，超预算就 `break`；最后 `segments.reversed.join('\n')`。
- `deleteForBook`：先查该书线程 id 列表，再删除这些线程的消息，最后删除线程；空列表不要拼 `IN ()`。
- `role` 用 `CompanionRole.fromName(row.role)` 映射。

- [ ] **Step 3: 运行仓储测试确认通过**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/data/companion_chat_repository_test.dart`
Expected: PASS（9 个测试）。

- [ ] **Step 4: 跑全量测试并提交**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿。

```bash
git add lib/data/repositories/companion_chat_repository.dart test/data/companion_chat_repository_test.dart
git commit -m "feat: add the companion chat repository"
```

---

### Task 3: 前序章节记忆进入助手上下文

**Files:**
- Modify: `lib/assistant/reading_context.dart`
- Modify: `lib/assistant/openai_assistant_service.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/domain/services/book_service.dart`
- Modify: `test/assistant/openai_assistant_service_test.dart`
- Modify: `test/domain/book_service_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `CompanionChatRepository`。
- Produces:
  - `ReadingContext` 新增 `final String companionMemory`（默认 `''`），构造参数与 `copyWith` 都可传。
  - `companionChatRepositoryProvider`，类型 `Provider<CompanionChatRepository>`，基于 `appDatabaseProvider`。
  - `BookService` 构造新增可选 `this.companionChats`（类型 `CompanionChatRepository?`）；`deleteBook` 调用 `await companionChats?.deleteForBook(book.id);`。
  - `OpenAiAssistantService._systemMessage` 在 `bookBrief` 之后、`chapterText` 之前加入：`'【此前章节的对话纪要】\n${context.companionMemory}'`（仅非空时）。

- [ ] **Step 1: 写失败的测试**

在 `test/assistant/openai_assistant_service_test.dart` 追加：

```dart
test('chat folds the prior-chapter memory into the system prompt', () async {
  final client = FakeLlmClient(reply: '后来家道中落。');
  final service = OpenAiAssistantService(client: client, config: configured);
  const withMemory = ReadingContext(
    bookTitle: '活着',
    chapterTitle: '第三章',
    chapterText: '现在的正文。',
    companionMemory: '【第一章】读者：福贵是谁？ 助手：地主家的少爷。',
  );

  await service.chat(withMemory, const [], '后来呢？').toList();

  expect(client.lastMessages.first.content, contains('【此前章节的对话纪要】'));
  expect(client.lastMessages.first.content, contains('地主家的少爷'));
});
```

在 `test/domain/book_service_test.dart` 顶部补 import：`companion_chat_repository.dart` 与 `companion_chat.dart`；在 `setUp` 里给 `BookService` 传入 `companionChats: CompanionChatRepository(db)`，并追加：

```dart
test('deleting a book removes its companion conversations', () async {
  final source = File('${temp.path}/chat.txt')..writeAsStringSync('第一章 开始\n内容');
  final book = await service.importFile(source.path);
  final chats = CompanionChatRepository(db);
  final thread = await chats.createThread(
    bookId: book.id,
    chapterIndex: 0,
    chapterTitle: '第一章',
  );
  await chats.appendMessage(
    threadId: thread.id,
    role: CompanionRole.user,
    content: '福贵是谁？',
  );

  await service.deleteBook(book);

  expect(await chats.threadsForBook(book.id), isEmpty);
  expect(await chats.messagesForThread(thread.id), isEmpty);
});
```

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/assistant/openai_assistant_service_test.dart test/domain/book_service_test.dart`
Expected: FAIL to compile / 断言失败 —— `companionMemory`、`companionChats`、`companionChatRepositoryProvider` 尚不存在。

- [ ] **Step 2: 实现上下文、提示、provider 与级联删除**

- `reading_context.dart`：字段、构造函数默认值、`copyWith` 三处都加 `companionMemory`。
- `openai_assistant_service.dart`：在 `if (context.bookBrief.isNotEmpty)` 之后加该段。
- `providers.dart`：在 `annotationRepositoryProvider` 附近添加：
  ```dart
  final companionChatRepositoryProvider = Provider<CompanionChatRepository>((ref) {
    return CompanionChatRepository(ref.watch(appDatabaseProvider));
  });
  ```
  并在 `bookServiceProvider` 的构造函数里加 `companionChats: ref.watch(companionChatRepositoryProvider),`。
- `book_service.dart`：import repository；构造参数与字段；`deleteBook` 在 `books.delete` 前调用级联。

- [ ] **Step 3: 运行测试确认通过**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/assistant/openai_assistant_service_test.dart test/domain/book_service_test.dart`
Expected: PASS。

- [ ] **Step 4: 跑全量测试并提交**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿。

```bash
git add lib/assistant/reading_context.dart lib/assistant/openai_assistant_service.dart lib/app/providers.dart lib/domain/services/book_service.dart test/assistant/openai_assistant_service_test.dart test/domain/book_service_test.dart
git commit -m "feat: feed prior-chapter conversation memory into the assistant"
```

---

### Task 4: 面板按线程持久化

**Files:**
- Modify: `lib/features/companion/companion_panel.dart`
- Modify: `test/features/companion_panel_test.dart`

**Interfaces:**
- Consumes: `companionChatRepositoryProvider`、`CompanionChatRepository`、`CompanionThread`、`CompanionRole`、`companionThreadTitle`、`ReadingContext.companionMemory`。
- Produces（供 Task 5/6 使用）：
  - `_CompanionPanelState` 新增字段：`_chats`、`CompanionThread? _thread`、`bool _autoTitlePending`、`int _requestToken`。
  - `Future<void> _ensureThread({required String firstMessage, String? titleIfNew})`。
  - `Future<void> _loadLatestThread()`。
  - `Future<void> _stream(Stream<String> Function(AssistantService) start, {required int token, Future<void> Function(String reply)? onComplete})`。
  - `CompanionPanel` 不变（新增的跳章回调在 Task 6 加）。

- [ ] **Step 1: 测试基础设施改造（先不改面板行为）**

在 `test/features/companion_panel_test.dart` 顶部加（`_ControlledAssistant` 需要 `dart:async`）：

```dart
import 'dart:async';

import 'package:drift/native.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/companion_chat_repository.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';
```

给 `_FakeAssistant` 增加记录字段：

```dart
List<ChatMessage>? lastHistory;
ReadingContext? lastContext;
```

在 `chat` 里赋值 `lastHistory = List.of(history); lastContext = context;`。

`_wrap` 增加 `AppDatabase? db` 与 `ValueNotifier<int>? chapter` 参数；默认创建内存库并用 `addTearDown(db.close)` 关闭。覆盖 `appDatabaseProvider`：

```dart
appDatabaseProvider.overrideWithValue(database),
```

面板外层用 `ValueListenableBuilder<int>`；`chapter` 为 null 时固定原值 `1`。增加两个等待辅助：

```dart
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _flush(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
```

`_ask` 改为在点击后调用 `_settle`。所有直接点「总结本章」后 `pumpAndSettle()` 的测试改成 `_settle`。此时全量测试应仍然全绿（面板还没改，DB override 只是备用）。

- [ ] **Step 2: 写失败的面板持久化测试**

追加一个可控助手（按调用返回新的单订阅流）：

```dart
class _ControlledAssistant implements AssistantService {
  final controllers = <StreamController<String>>[];
  final histories = <List<ChatMessage>>[];
  final contexts = <ReadingContext>[];

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage,
  ) {
    contexts.add(context);
    histories.add(List.of(history));
    final controller = StreamController<String>();
    controllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) async* {
    yield '摘要';
  }
  // explain / translate 同 _FakeAssistant
}
```

测试：

```dart
testWidgets('a saved conversation reopens with the panel', (tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  late CompanionThread thread;
  await tester.runAsync(() async {
    final repo = CompanionChatRepository(db);
    thread = await repo.createThread(
      bookId: 'book-1', chapterIndex: 1, chapterTitle: '第二章', title: '福贵',
    );
    await repo.appendMessage(
      threadId: thread.id, role: CompanionRole.user, content: '福贵为什么败家？',
    );
    await repo.appendMessage(
      threadId: thread.id, role: CompanionRole.assistant, content: '因为赌博。',
    );
  });

  await tester.pumpWidget(_host(_FakeAssistant(), db: db));
  await _settle(tester);

  expect(find.text('福贵为什么败家？'), findsOneWidget);
  expect(find.text('因为赌博。'), findsOneWidget);
});

testWidgets('the question is stored before the reply finishes', (tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final fake = _ControlledAssistant();
  await tester.pumpWidget(_host(fake, db: db));
  await _settle(tester);

  await tester.enterText(find.byType(TextField), '福贵为什么败家？');
  await tester.tap(find.byTooltip('发送'));
  await _flush(tester);

  final rows = await tester.runAsync(
    () => CompanionChatRepository(db).threadsForBook('book-1'),
  );
  expect(rows, hasLength(1));
  final stored = await tester.runAsync(
    () => CompanionChatRepository(db).messagesForThread(rows!.single.id),
  );
  expect(stored!.map((m) => m.content), contains('福贵为什么败家？'));
  expect(stored.where((m) => m.role == CompanionRole.assistant), isEmpty);
});

testWidgets('the model sees the last eight messages and the prior digest',
    (tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final fake = _FakeAssistant();
  await tester.runAsync(() async {
    final repo = CompanionChatRepository(db);
    final prior = await repo.createThread(
      bookId: 'book-1', chapterIndex: 0, chapterTitle: '第一章', title: '前文',
    );
    await repo.appendMessage(
      threadId: prior.id, role: CompanionRole.user, content: '前文问答',
    );
    final later = await repo.createThread(
      bookId: 'book-1', chapterIndex: 3, chapterTitle: '第四章', title: '未来',
    );
    await repo.appendMessage(
      threadId: later.id, role: CompanionRole.user, content: '未来剧透',
    );
    final current = await repo.createThread(
      bookId: 'book-1', chapterIndex: 1, chapterTitle: '第二章', title: '当前',
    );
    for (var i = 1; i <= 10; i++) {
      await repo.appendMessage(
        threadId: current.id,
        role: i.isOdd ? CompanionRole.user : CompanionRole.assistant,
        content: 'm$i',
      );
    }
  });

  await tester.pumpWidget(_host(fake, db: db));
  await _settle(tester);
  await tester.enterText(find.byType(TextField), '新问题');
  await tester.tap(find.byTooltip('发送'));
  await _settle(tester);

  expect(fake.lastHistory, hasLength(8));
  expect(fake.lastHistory!.first.content, 'm3');
  expect(fake.lastHistory!.last.content, 'm10');
  expect(
    fake.lastHistory!.where((m) => m.content == '新问题'),
    isEmpty,
    reason: 'the current question must only be sent once',
  );
  expect(fake.lastContext!.companionMemory, contains('前文问答'));
  expect(fake.lastContext!.companionMemory, isNot(contains('未来剧透')));
});

testWidgets('switching chapters drops the reply that was still streaming',
    (tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final fake = _ControlledAssistant();
  final chapter = ValueNotifier(1);
  addTearDown(chapter.dispose);
  await tester.pumpWidget(_host(fake, db: db, chapter: chapter));
  await _settle(tester);

  await tester.enterText(find.byType(TextField), '旧章问题');
  await tester.tap(find.byTooltip('发送'));
  await _flush(tester);

  chapter.value = 2;
  await _flush(tester);

  fake.controllers.last.add('迟到的回答');
  await fake.controllers.last.close();
  await _settle(tester);

  expect(find.text('迟到的回答'), findsNothing);
  final rows = await tester.runAsync(
    () => CompanionChatRepository(db).threadsForBook('book-1'),
  );
  for (final thread in rows!) {
    final messages = await tester.runAsync(
      () => CompanionChatRepository(db).messagesForThread(thread.id),
    );
    expect(messages!.where((m) => m.content == '迟到的回答'), isEmpty);
  }
});

testWidgets('a failed reply keeps the question and drops the partial answer',
    (tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(_host(_FailingAssistant(), db: db));
  await _settle(tester);

  await tester.enterText(find.byType(TextField), '会失败的问题');
  await tester.tap(find.byTooltip('发送'));
  await _settle(tester);

  final repo = CompanionChatRepository(db);
  final threads = await tester.runAsync(() => repo.threadsForBook('book-1'));
  final stored = await tester.runAsync(
    () => repo.messagesForThread(threads!.single.id),
  );
  expect(stored!.map((m) => m.content), ['会失败的问题']);
  expect(stored.where((m) => m.role == CompanionRole.assistant), isEmpty);
  expect(find.textContaining('出错了'), findsOneWidget);
  expect(find.textContaining('半截'), findsNothing);
});
```

其中 `_FailingAssistant` 的 `chat` 先 `yield '半截'` 再 `throw Exception('boom')`，其余方法同 `_FakeAssistant`。

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/companion_panel_test.dart`
Expected: FAIL —— 重开里看不到已存消息；提问请求不是先落库；历史窗口与 digest 未接线；切章后迟到回复仍显示/落库。

- [ ] **Step 3: 实现面板持久化**

按以下行为改写 `_CompanionPanelState`（保留现有 TTS、键盘处理、气泡）：

- `initState`：`_chats = ref.read(companionChatRepositoryProvider);` 然后 `unawaited(_loadLatestThread());`。加载期间不显示动画进度条（避免 `pumpAndSettle` 卡住）。
- `_loadLatestThread()`：先记 `final token = _requestToken;`；`_thread = await _chats.latestThreadForChapter(...)` 与消息加载完成后，若 `!mounted || token != _requestToken` 丢弃结果；有线程则映射成 `_history`；无线程则 `_thread=null; _history=[]`；`_autoTitlePending=false`。
- `didUpdateWidget`：当 `bookId` 或 `chapterIndex` 变化时：`_requestToken++`、`_busy=false`、`_streaming=''`、`_error=null`、`_speakingIndex=null`、`_thread=null`、`_history=[]`、`_autoTitlePending=false`，`unawaited(_tts.stop())`，然后 `unawaited(_loadLatestThread())`。
- `_ensureThread({required String firstMessage, String? titleIfNew})`：
  - 已有 `_thread`：若 `_autoTitlePending`，`_autoTitlePending=false`，把标题改为 `companionThreadTitle(firstMessage)` 并 `renameThread`；
  - 没有：`createThread(bookId, chapterIndex: widget.chapterIndex, chapterTitle: widget.chapterTitle, title: titleIfNew ?? companionThreadTitle(firstMessage))`。
- `_send()`：
  1. `text = _input.text.trim()`；空、`_busy`、只读（Task 6 字段尚未加，先忽略）直接返回；
  2. 若当前未配置模型（`ref.read(assistantServiceProvider).value?.isConfigured != true`）直接返回，避免把发不出去的问题落库；
  3. `_input.clear()`；`final token = _requestToken;`
  4. `final thread = await _ensureThread(firstMessage: text);`
  5. `await _chats.appendMessage(threadId: thread.id, role: user, content: text);`
  6. `setState(() => _history.add(ChatMessage(role: user, content: text)));`
  7. 取窗口：`final priorCount = _history.length - 1; final start = priorCount > 8 ? priorCount - 8 : 0; final prior = _history.sublist(start, priorCount);`
  8. `final memory = await _chats.memoryDigest(bookId: widget.bookId, beforeChapterIndex: widget.chapterIndex);`
  9. `await _stream((s) => s.chat(_context.copyWith(companionMemory: memory), prior, text), token: token, onComplete: (reply) => _chats.appendMessage(threadId: thread.id, role: assistant, content: reply));`
- `_summarize()`：同样先 await `_ensureThread(firstMessage: '总结本章', titleIfNew: '总结本章')`，写入一条 user 消息 `'总结本章'` 并加入 `_history`，计算 memory，然后 `_stream((s) => s.summarizeChapter(_context.copyWith(companionMemory: memory)), ...)`，完成回调写 assistant 消息。
- `_stream`：
  - 开始时 `setState(_busy=true; _streaming=''; _error=null)`；
  - 每收到 chunk，若 `!mounted || token != _requestToken` 就 `break`，不再 setState；
  - 流结束后若 token 失效直接 return；
  - 回复非空时先 `await onComplete?.call(reply)`，再 setState 把 assistant 消息加入 `_history`、清空 `_streaming`，并按 `_autoSpeak` 朗读；回复为空也要清空 `_streaming`；
  - `catch` 写中文错误并清空 `_streaming`（半截回复不留在界面上）；`finally` 仅在 `mounted && token == _requestToken` 时清 `_busy`。
- 聊天列表顶部加记忆提示容器（key `companion-memory-chip`）：
  - `widget.chapterIndex == 0` → `暂无前序章节对话`
  - 否则 → `引用之前章节的对话纪要（≤400 字），不读取后面的章节`
- 空聊天时保持可输入；未配置时仍走现有「去设置」整块（Task 5 再调整为历史可用）。

- [ ] **Step 4: 运行面板测试确认通过**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/companion_panel_test.dart`
Expected: PASS（原有 10 个 + 新增 5 个）。

- [ ] **Step 5: 跑全量测试并提交**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿。

```bash
git add lib/features/companion/companion_panel.dart test/features/companion_panel_test.dart
git commit -m "feat: persist companion messages per chapter thread"
```

---

### Task 5: 历史管理与线程增删改

**Files:**
- Create: `lib/features/companion/companion_history.dart`
- Modify: `lib/features/companion/companion_panel.dart`
- Create: `test/features/companion_history_test.dart`
- Modify: `test/features/companion_panel_test.dart`

**Interfaces:**
- Consumes: `CompanionThread`、`formatCompanionTime`、repository 的线程/消息方法。
- Produces:
  - `String formatCompanionTime(DateTime time, {DateTime? now})`：`刚刚` / `N 分钟前` / `今天 HH:mm` / `昨天 HH:mm` / `M月d日` / `YYYY年M月d日`。
  - `class CompanionHistoryView extends StatefulWidget`，构造参数：
    ```dart
    final List<CompanionThread> threads;
    final int currentChapterIndex;
    final bool loading;
    final VoidCallback onNewThread;
    final ValueChanged<CompanionThread> onOpen;
    final void Function(CompanionThread thread, String title) onRename;
    final ValueChanged<CompanionThread> onDelete;
    ```
  - 面板新增 `_CompanionView { chat, history }`、`_view`、`List<CompanionThread> _threads`、`bool _threadsLoading`、`CompanionThread? _readOnlyThread`，以及 `_loadThreads`、`_newThread`、`_renameThread`、`_deleteThread`、`_openThread`。
  - 面板头部下方两个标签：`聊天` / `历史`；key `companion-tab-chat` / `companion-tab-history`。

- [ ] **Step 1: 写失败的历史视图与面板测试**

`test/features/companion_history_test.dart`（先加一个 `CompanionThread _thread({required String id, required int chapterIndex, required String chapterTitle, required String title})` 辅助，`createdAt/updatedAt` 用固定时间）：

```dart
test('recent times fall back from minutes to dates', () {
  final now = DateTime(2026, 11, 4, 15, 30);
  expect(formatCompanionTime(now.subtract(const Duration(seconds: 20)), now: now), '刚刚');
  expect(formatCompanionTime(now.subtract(const Duration(minutes: 5)), now: now), '5 分钟前');
  expect(formatCompanionTime(DateTime(2026, 11, 4, 9, 5), now: now), '今天 09:05');
  expect(formatCompanionTime(DateTime(2026, 11, 3, 22, 0), now: now), '昨天 22:00');
  expect(formatCompanionTime(DateTime(2026, 10, 1, 8, 0), now: now), '10月1日');
  expect(formatCompanionTime(DateTime(2025, 10, 1, 8, 0), now: now), '2025年10月1日');
});

testWidgets('the current chapter is listed first and marked', (tester) async {
  final threads = [
    _thread(id: 'old', chapterIndex: 0, chapterTitle: '第一章', title: '旧章节对话'),
    _thread(id: 'now', chapterIndex: 2, chapterTitle: '第三章', title: '当前对话'),
  ];
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: CompanionHistoryView(
    threads: threads,
    currentChapterIndex: 2,
    loading: false,
    onNewThread: () {},
    onOpen: (_) {},
    onRename: (_, __) {},
    onDelete: (_) {},
  ))));

  expect(find.text('当前章'), findsOneWidget);
  expect(find.text('只读'), findsOneWidget);
  expect(
    tester.getTopLeft(find.text('当前对话')).dy,
    lessThan(tester.getTopLeft(find.text('旧章节对话')).dy),
  );
});

testWidgets('rename saves the trimmed title and cancel keeps the old one',
    (tester) async {
  CompanionThread? renamed;
  String? title;
  // threads: 一条当前章线程，key 'companion-thread-menu-t1'
  // 点菜单 → 点 key('companion-menu-rename') → 输入 '  新名字  ' → 点 key('companion-rename-save')
  // expect(title, '新名字')
  // 再点菜单 → 重命名 → 点 key('companion-rename-cancel') → 没有新的 onRename 调用
});

testWidgets('delete asks the panel to remove the thread', (tester) async {
  // 点菜单 → key('companion-menu-delete') → expect(onDelete 收到的 id, 't1')
});
```

`test/features/companion_panel_test.dart` 追加：

```dart
testWidgets('a new conversation is renamed after its first message', (tester) async {
  // 配置好的 _FakeAssistant；pump；点 companion-tab-history；_settle
  // 点 companion-new-thread：面板自动切回聊天
  // 再点 companion-tab-history；_settle：出现 '新对话' 与 '共 0 条'
  // 点 companion-tab-chat，发送 '你好世界'
  // _settle 后 threadsForBook 的 title 是 '你好世界'
});

testWidgets('deleting the only thread returns to an empty chat', (tester) async {
  // 种子一条当前章线程；打开历史；点菜单 → 删除
  // expect(threadsForBook, isEmpty)
  // 历史显示 '还没有对话'
});

testWidgets('deleting the open thread falls back to the latest one',
    (tester) async {
  // 同一章种子两条线程：'旧对话' 与 '新对话'（后者 updatedAt 更晚）
  // 让面板当前打开 '新对话'，从历史删除它
  // expect(消息列表切换到 '旧对话' 的消息，且仍可输入)
});

testWidgets('deleting a thread stops the reply it was generating', (tester) async {
  // _ControlledAssistant；发送后 _flush；打开历史；删除当前线程
  // fake.controllers.last.add('迟到的回答')；close；_settle
  // expect(find.text('迟到的回答'), findsNothing)
  // threadsForBook 为空；messagesForThread(oldId) 为空
});

testWidgets('an unconfigured panel still browses saved history', (tester) async {
  // 种子一条当前章线程（'旧问题'/'旧回答'）；_host(const UnconfiguredAssistantService())
  // 点 companion-tab-history；_settle；点该线程行
  // expect(find.text('旧问题'), findsOneWidget)
  // expect(find.byType(TextField), findsNothing)
  // expect(find.text('去设置'), findsOneWidget)
});
```

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/companion_history_test.dart test/features/companion_panel_test.dart`
Expected: FAIL to compile / 断言失败 —— 历史视图与标签不存在。

- [ ] **Step 2: 实现历史视图**

`CompanionHistoryView` 行为：

- `threads` 按 `chapterIndex` 分组；组顺序：当前章第一，其余按 `chapterIndex` 升序。
- 组标题用第一条线程的 `chapterTitle`；当前章显示 `当前章`，其他章显示 `只读`。
- 每行 key `companion-thread-<id>`：标题（单行，`overflow: TextOverflow.ellipsis`）、`formatCompanionTime(updatedAt)`、`共 <messageCount> 条`。
- 右侧 `PopupMenuButton<String>`，key `companion-thread-menu-<id>`，两项：`重命名`（key `companion-menu-rename`）、`删除`（key `companion-menu-delete`）。
- 点重命名把该行替换成 `TextField`（key `companion-rename-field`）+ 保存图标（key `companion-rename-save`）+ 取消图标（key `companion-rename-cancel`）；保存时 `trim()` 为空则不调用 `onRename`，否则调用并退出编辑。
- 顶部一行：`新对话` 按钮 key `companion-new-thread`。
- 空列表显示 `还没有对话`；`loading` 时显示非动画文案 `加载中…`。

- [ ] **Step 3: 接入面板**

- 头部保留标题、「停止朗读」「总结本章」「关闭」，其下加两个标签（key 见上）；`_view` 控制显示聊天或历史。
- `_selectTab(history)`：切到历史并 `unawaited(_loadThreads())`；`_selectTab(chat)`：若 `_readOnlyThread != null`，先按 `_thread?.id` 重新加载当前线程消息（没有当前线程就回到空状态），再清 `_readOnlyThread`。
- `_loadThreads()`：`_threads = await _chats.threadsForBook(widget.bookId)`，`_threadsLoading` 包住。
- `_newThread()`：若 `_busy` 先 `_requestToken++` 让旧回复失效；`createThread(..., title: '新对话')`；置 `_thread`、清空 `_history`、`_autoTitlePending = true`、`_view = chat`；刷新 `_threads`。
- `_renameThread(thread, title)`：`renameThread`；刷新 `_threads`；若 `_thread?.id == thread.id` 同步 `_thread` 标题。
- `_deleteThread(thread)`：若正在生成的正是它，先 `_requestToken++`、`_busy=false`、`_streaming=''`；`deleteThread`；刷新 `_threads`；若删的是 `_thread`，加载该章最近线程（没有则空状态）。
- `_openThread(thread)`：加载全部消息；`chapterIndex == widget.chapterIndex` 时设为当前线程并可输入、清 `_readOnlyThread`；否则设 `_readOnlyThread = thread` 并隐藏输入框（只读横幅与「前往该章」按钮由 Task 6 补）。
- **未配置模型分支调整**：头部与标签始终显示。聊天标签下：`_history` 为空时显示原有「未配置 AI 服务 / 去设置」；非空时显示消息列表，底部用一行提示 `未配置 AI 服务，请到设置页填写` 加一个 `去设置` 按钮（无输入框）。历史标签始终可用。

- [ ] **Step 4: 运行历史与面板测试确认通过**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/companion_history_test.dart test/features/companion_panel_test.dart`
Expected: PASS。

- [ ] **Step 5: 跑全量测试并提交**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿。

```bash
git add lib/features/companion/companion_history.dart lib/features/companion/companion_panel.dart test/features/companion_history_test.dart test/features/companion_panel_test.dart
git commit -m "feat: add companion conversation history management"
```

---

### Task 6: 旧章节只读回看与跳章

**Files:**
- Modify: `lib/features/companion/companion_panel.dart`
- Modify: `lib/features/reader/reader_page.dart`
- Modify: `test/features/companion_panel_test.dart`
- Modify: `test/features/reader_companion_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `_openThread` / `_view` / `_thread`。
- Produces:
  - `CompanionPanel` 构造新增 `final ValueChanged<int>? onGoToChapter;`。
  - 面板字段：`String? _pendingThreadId`、`int? _pendingChapterIndex`；只读状态复用 Task 5 的 `_readOnlyThread`。
  - 阅读器 `_toggleCompanion` 的底部面板传入：
    ```dart
    onGoToChapter: (index) {
      Navigator.of(context).pop();
      _goToChapter(index);
    },
    ```
  - 阅读器 `_buildCompanionPanel` 的停靠面板传入 `onGoToChapter: _goToChapter`。

- [ ] **Step 1: 写失败的只读与跳章测试**

面板测试：

```dart
testWidgets('an old chapter thread opens read-only with a jump button',
    (tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.runAsync(() async {
    final repo = CompanionChatRepository(db, newId: () => 'id-0');
    final old = await repo.createThread(
      bookId: 'book-1', chapterIndex: 1, chapterTitle: '第二章', title: '旧对话',
    );
    await repo.appendMessage(
      threadId: old.id, role: CompanionRole.user, content: '旧问题',
    );
    await repo.appendMessage(
      threadId: old.id, role: CompanionRole.assistant, content: '旧回答',
    );
  });
  int? jumped;

  await tester.pumpWidget(_host(
    _FakeAssistant(),
    db: db,
    chapterIndex: 2,
    onGoToChapter: (index) => jumped = index,
  ));
  await _settle(tester);
  await tester.tap(find.byKey(const Key('companion-tab-history')));
  await _settle(tester);
  await tester.tap(find.byKey(const Key('companion-thread-id-0')));
  await _settle(tester);

  expect(find.text('保存在第 2 章，当前为只读'), findsOneWidget);
  expect(find.text('旧问题'), findsOneWidget);
  expect(find.text('旧回答'), findsOneWidget);
  expect(find.byType(TextField), findsNothing);
  expect(find.text('总结本章'), findsOneWidget);
  expect(
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, '总结本章'))
        .onPressed,
    isNull,
  );

  await tester.tap(find.byKey(const Key('companion-go-to-chapter')));
  expect(jumped, 1);
});
```

（线程 id 由测试固定：给 `CompanionChatRepository` 传 `newId: () => 'id-${ids++}'`，第一条即 `id-0`。把 Task 4 改过的 `_host` / `_wrap` 再扩成：`AppDatabase? db`、`ValueNotifier<int>? chapter`、`int chapterIndex = 1`、`ValueChanged<int>? onGoToChapter`；`chapterTitle` 统一取当前索引对应的 `'第${index + 1}章'`。）

阅读器集成测试，宽窗口。先给 `reader_companion_test.dart` 加一个返回固定回答的 `_EchoAssistant`（`isConfigured => true`），把 `pumpReader` 的 `overrides` 增加 `assistantServiceProvider.overrideWith((ref) async => _EchoAssistant())`（这样面板才显示输入框）；再照面板测试加一个 `_flush` 辅助（不能对生成中的进度条用 `pumpAndSettle`）：

```dart
testWidgets('jumping from an old thread opens that thread in its chapter',
    (tester) async {
  // 在 setUp 里追加第二章；用 CompanionChatRepository(db, newId: () => 'id-0')
  // 给 b1 chapterIndex:1 建一条线程，写入 '旧问题' / '旧回答'
  useWindow(tester, const Size(1400, 900));
  await pumpReader(tester);
  await tester.tap(find.byTooltip('陪读'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('companion-tab-history')));
  await _flush(tester);
  await tester.tap(find.byKey(const Key('companion-thread-id-0')));
  await _flush(tester);
  await tester.tap(find.byKey(const Key('companion-go-to-chapter')));
  await _flush(tester);

  expect(find.textContaining('陪读 · 第二章'), findsOneWidget);
  expect(find.text('旧回答'), findsOneWidget);
  expect(find.text('保存在第 2 章，当前为只读'), findsNothing);
  expect(find.byType(TextField), findsOneWidget);
});
```

窄窗口（底部面板）：

```dart
testWidgets('a narrow window closes the sheet and lands on the chapter',
    (tester) async {
  // 同样的两章 + 一条第二章线程
  useWindow(tester, const Size(800, 900));
  await pumpReader(tester);
  await tester.tap(find.byTooltip('陪读'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('companion-tab-history')));
  await _flush(tester);
  await tester.tap(find.byKey(const Key('companion-thread-id-0')));
  await _flush(tester);
  await tester.tap(find.byKey(const Key('companion-go-to-chapter')));
  await _flush(tester);
  await tester.pumpAndSettle();

  expect(find.byType(BottomSheet), findsNothing);
  await tester.tap(find.byTooltip('陪读'));
  await tester.pumpAndSettle();
  expect(find.textContaining('陪读 · 第二章'), findsOneWidget);
});
```

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/companion_panel_test.dart test/features/reader_companion_test.dart`
Expected: FAIL —— 只读视图与 `onGoToChapter` 不存在，跳章后侧栏不会打开指定线程。

- [ ] **Step 2: 实现只读视图与跳章**

- 只读状态使用 Task 5 的 `_readOnlyThread`：打开旧章节线程时 `_thread` 保持不变（仍记当前章的线程），加载全部消息，隐藏输入框，头部「总结本章」在 `_readOnlyThread != null` 时禁用。
- 聊天标签内容顶部显示提示：`'保存在第 ${thread.chapterIndex + 1} 章，当前为只读'`（只读时不显示记忆提示）；底部 `FilledButton` key `companion-go-to-chapter`，文案 `前往该章`：
  ```dart
  _pendingThreadId = thread.id;
  _pendingChapterIndex = thread.chapterIndex;
  widget.onGoToChapter?.call(thread.chapterIndex);
  ```
- `didUpdateWidget` 在章变化且 `_pendingThreadId != null && widget.chapterIndex == _pendingChapterIndex` 时：按 id 加载该线程（可输入），清空 pending；否则加载该章最近线程。
- 从只读回到 `聊天` 标签：按 Task 5 的 `_selectTab(chat)` 逻辑恢复当前章线程的消息并清 `_readOnlyThread`。
- 阅读器两处传参（见 Interfaces）。停靠侧栏保留面板 state，跳章后由 `didUpdateWidget` 选择来源线程；底部面板跳章时先 `pop`，重新打开走「最近线程」。

- [ ] **Step 3: 运行面板与阅读器测试确认通过**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/companion_panel_test.dart test/features/reader_companion_test.dart`
Expected: PASS。

- [ ] **Step 4: 跑全量测试并提交**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿。

```bash
git add lib/features/companion/companion_panel.dart lib/features/reader/reader_page.dart test/features/companion_panel_test.dart test/features/reader_companion_test.dart
git commit -m "feat: reopen old chapter conversations and jump to them"
```

---

### Task 7: 文档、静态检查与全量验证

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Add: `docs/superpowers/specs/2026-11-04-companion-chat-memory-design.md`
- Add: `docs/superpowers/plans/2026-11-04-companion-chat-memory.md`

**Interfaces:**
- Consumes: 前六个任务的实现。
- Produces: 与代码一致的测试数量与功能说明。

- [ ] **Step 1: 静态检查与全量测试**

Run: `F:/src/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿。记录实际通过数（用输出里的 `All tests passed!` 前一行或 `+N` 计数）。

- [ ] **Step 2: 更新文档**

- `README.md` 第 25 行「陪读对话」段落改为同时描述：按章节保存、可新建/重命名/删除、历史页按章分组、旧章节只读并可「前往该章」、只记忆前序章节对话纪要（≤400 字）不读后续章节。
- `CONTRIBUTING.md` 第 27 行「陪读」段落补一句相同的持久化记忆说明。
- `README.md` 第 85 行、`CONTRIBUTING.md` 第 32 与 117 行的数字改为 Step 1 的实际测试数。
- 若 README 的「已知限制」提到陪读无历史，删除该说法；没有就不要新增。

- [ ] **Step 3: 再跑一次全量测试并提交**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全绿。

```bash
git add README.md CONTRIBUTING.md docs/superpowers/specs/2026-11-04-companion-chat-memory-design.md docs/superpowers/plans/2026-11-04-companion-chat-memory.md
git commit -m "docs: document companion chat memory"
```

---

## 计划自检

- **Spec 覆盖**：schema v10（Task 1）、记忆装配与 400 字上限（Task 2 + 4）、用户/助手落库时机与切章取消（Task 4）、书籍级联删除（Task 3）、线程新建/重命名/删除/分组（Task 5）、旧章节只读与跳章（Task 6）、未配置模型仍可看历史（Task 5）、总结本章入线程（Task 4）、文档与全量验证（Task 7）。
- **类型一致性**：`CompanionChatRepository` 的方法名在 Task 2 定义，Task 3/4/5/6 只按该签名调用；`CompanionThread.messageCount` 由 `threadsForBook` 填充，其余查询默认 0；`companionMemory` 只在 Task 3 定义、Task 4 消费。
- **Review Focus**：五条风险各自绑定到 Task 4/5/6 的测试。
- **比例**：计划以大颗粒接口与断言为主，未逐行复述实现；每个任务都给出可运行命令、预期结果与提交步骤。
