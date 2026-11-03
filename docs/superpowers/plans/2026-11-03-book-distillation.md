# Book Distillation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app book distillation pipeline (overview / chapter map / cards / tone) plus a companion chat context that gives the model the whole book's gist and the chapter the reader is in.

**Architecture:** A stage pipeline (plan → map → reduce-1 → reduce-2 → cards → verify) over chapter-anchored segments, persisted in three drift tables for resumable runs. `DistilledContextAssembler` turns stored artifacts into a bounded prompt preamble consumed by a decorator service (`DigestAwareAssistantService`) that wraps the existing `AssistantService` without changing its signatures. LLM access is a dependency-free `dart:io` OpenAI-compatible client.

**Tech Stack:** Flutter 3.x / Dart 3.13, riverpod 3 (manual providers, no codegen), drift 2.35 (schema v5), `dart:io HttpClient`, `dart:convert`.

**Spec:** `docs/superpowers/specs/2026-11-03-book-distillation-design.md`

## Global Constraints

- No new pub dependencies: HTTP via `dart:io HttpClient`, JSON via `dart:convert`, API key stored in the existing `Settings` table under `llm.apiKey` (plaintext; documented tradeoff, secure storage is a follow-up).
- `AssistantService` method signatures are frozen: `translate`, `explain`, `summarizeChapter`, `chat` must not change. `ReadingContext` may gain only optional fields.
- PDF books are not distillable in this version; txt/epub only. `BookFormat.pdf` → entry disabled with a readable reason.
- All user-facing copy is Simplified Chinese. Comments and commit messages are English.
- Distillation units never cross a reader chapter boundary. `unitKey` is `seg-0007` / `part-02` / `overview` / `tone` / `cards-01` / `verify-01`.
- Call budget per book is a soft target ≤80 completions; tests assert `<= 80` with the fake client.
- Pipeline version is `1`; bumping `DistillPipeline.pipelineVersion` or changing chunking invalidates old artifacts.
- Every task ends with `flutter analyze` clean and its own tests green; existing 22 test files stay green.

## Review Focus

- **A book that is one giant chapter** (`txt_chapter_detector` fallback 「正文」): segmentation must still produce ≥2 segments and a usable overview, never one unbounded prompt.
- **Reading position at 90% of a long chapter**: the excerpt window must contain the text the reader sees, and the spoiler guard must key off `chapterIndex`, not text matching.
- **Missing/wrong API key**: every entry point degrades to a readable message, never throws into the widget tree, and reading stays usable.
- **Cancel/pause mid-run**: no request is issued after cancel and a restart resumes from completed units instead of re-billing them.
- **Stale artifacts**: a changed `contentHash` or bumped `pipelineVersion` must block silent reuse of old output.

---

### Task 1: LLM config model and persistence

**Files:**
- Create: `lib/distill/llm/llm_config.dart`
- Test: `test/distill/llm_config_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class LlmConfig {
    const LlmConfig({required this.baseUrl, required this.model, required this.apiKey,
      this.temperature = 0.3, this.maxChunkChars = 6000});
    static const defaults = LlmConfig(baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat', apiKey: '');
    bool get isConfigured;                       // baseUrl/model/apiKey all non-empty after trim
    LlmConfig copyWith({String? baseUrl, String? model, String? apiKey, double? temperature, int? maxChunkChars});
    static const baseUrlKey = 'llm.baseUrl';
    static const modelKey = 'llm.model';
    static const apiKeyKey = 'llm.apiKey';
    static const temperatureKey = 'llm.temperature';
    static const maxChunkCharsKey = 'llm.maxChunkChars';
  }
  class LlmConfigStore {
    LlmConfigStore(SettingsRepository settings);
    Future<LlmConfig> load();                    // missing keys fall back to defaults
    Future<void> save(LlmConfig config);
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
test('defaults have no api key and are not configured', () {
  expect(LlmConfig.defaults.isConfigured, isFalse);
  expect(LlmConfig.defaults.baseUrl, 'https://api.deepseek.com/v1');
});

test('store round-trips config through settings', () async {
  final db = AppDatabase(NativeDatabase.memory());
  final store = LlmConfigStore(SettingsRepository(db));
  await store.save(const LlmConfig(baseUrl: 'http://x/v1', model: 'm', apiKey: 'k', temperature: 0.5, maxChunkChars: 3000));
  final loaded = await store.load();
  expect(loaded.isConfigured, isTrue);
  expect(loaded.maxChunkChars, 3000);
  expect(loaded.temperature, 0.5);
  await db.close();
});

test('malformed temperature falls back to default', () async {
  // settings row temperature='abc' → load() returns 0.3
});
```

- [ ] **Step 2: Run it, expect FAIL** — `flutter test test/distill/llm_config_test.dart` (file not found / class undefined).

- [ ] **Step 3: Implement** `LlmConfig` (immutable, `==`/`hashCode` not required) and `LlmConfigStore` using `SettingsRepository.get/set`; parse `double.tryParse` / `int.tryParse`, fall back to defaults on null or malformed values.

- [ ] **Step 4: Run the test, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add lib/distill/llm/llm_config.dart test/distill/llm_config_test.dart
git commit -m "feat: add llm config store backed by settings"
```

---

### Task 2: SSE parser and OpenAI-compatible client

**Files:**
- Create: `lib/distill/llm/llm_client.dart` (messages, error, abstract client, `CancelToken`)
- Create: `lib/distill/llm/sse.dart`
- Create: `lib/distill/llm/openai_llm_client.dart`
- Test: `test/distill/sse_test.dart`, `test/distill/openai_llm_client_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum LlmRole { system, user, assistant }
  class LlmMessage { const LlmMessage(this.role, this.content); final LlmRole role; final String content; }
  class LlmException implements Exception { LlmException(this.message, {this.statusCode}); }
  class CancelToken { bool get isCanceled; void cancel(); }

  abstract class LlmClient {
    Stream<String> streamChat(List<LlmMessage> messages, {double? temperature, int? maxTokens});
    Future<String> completeJson(List<LlmMessage> messages, {double? temperature, int? maxTokens, CancelToken? cancel});
    void dispose();
  }

  class OpenAiLlmClient implements LlmClient {
    OpenAiLlmClient({required LlmConfig Function() config, HttpClient? httpClient});
  }

  /// Returns the payload after `data: `, or null for non-data lines. '[DONE]' is returned verbatim.
  String? ssePayload(String line);
  ```
- `streamChat` yields content deltas; `completeJson` performs a non-streaming POST and returns `choices[0].message.content`. Non-200 → `LlmException('HTTP $status: body-snippet', statusCode: status)`. Timeouts: `connectionTimeout: 15s`, per-request `timeout(30s)`; timeout → `LlmException('请求超时')`. `cancel()` closes the in-flight `HttpClientRequest`/response subscription.

- [ ] **Step 1: Write failing tests**

```dart
test('ssePayload reads data lines only', () {
  expect(ssePayload('data: {"a":1}'), '{"a":1}');
  expect(ssePayload('event: ping'), isNull);
  expect(ssePayload('data: [DONE]'), '[DONE]');
});

test('streamChat yields deltas and stops on DONE', () async {
  // HttpServer on 127.0.0.1:0 answering:
  // data: {"choices":[{"delta":{"content":"你"}}]}\n\n data: {"choices":[{"delta":{"content":"好"}}]}\n\n data: [DONE]\n\n
  expect(await client.streamChat([...]).toList(), ['你', '好']);
});

test('completeJson maps 401 to a readable error', () async {
  expect(() => client.completeJson([...]), throwsA(isA<LlmException>().having((e) => e.statusCode, 'status', 401)));
});

test('cancel stops the stream without throwing', () async { ... });
```

- [ ] **Step 2: FAIL** — `flutter test test/distill/sse_test.dart test/distill/openai_llm_client_test.dart`.

- [ ] **Step 3: Implement** with `HttpClient` + `utf8.decoder` + `LineSplitter`, reading the body line-by-line so a partial JSON line never fires early. Header: `Authorization: Bearer <apiKey>`, `Content-Type: application/json`. Body: `{model, messages, stream, temperature, max_tokens?}`, role mapping `LlmRole.name`.

- [ ] **Step 4: PASS.**

- [ ] **Step 5: Commit** `feat: add openai-compatible llm client with sse streaming`

---

### Task 3: Settings page and providers

**Files:**
- Create: `lib/features/settings/settings_page.dart`
- Modify: `lib/app/providers.dart` (add `llmConfigStoreProvider`, `llmClientProvider`)
- Modify: `lib/features/library/library_page.dart` (AppBar settings icon)
- Test: `test/features/settings_page_test.dart`

**Interfaces:**
- Produces:
  ```dart
  final llmConfigStoreProvider = Provider<LlmConfigStore>((ref) => LlmConfigStore(ref.watch(settingsRepositoryProvider)));
  final llmClientProvider = Provider<LlmClient>((ref) { ... });  // reads config lazily per call
  class SettingsPage extends ConsumerStatefulWidget { const SettingsPage({super.key}); }
  ```
- `SettingsPage` fields: baseUrl, model, apiKey (obscured), temperature (0–2), maxChunkChars (2000–20000). Buttons: 保存, 测试连接 (calls `completeJson([LlmMessage(user, 'ping')])`, shows 「连接成功」/「连接失败：…」).

- [ ] **Step 1: Failing widget test** — pump `SettingsPage` with `llmClientProvider` overridden by a fake that returns `'pong'`; enter a key, tap 测试连接, expect 「连接成功」; save and expect `LlmConfigStore.load()` to reflect the typed values.

- [ ] **Step 2: FAIL** — `flutter test test/features/settings_page_test.dart`.

- [ ] **Step 3: Implement** the form (validators: baseUrl must start with http, key non-empty, ints in range), save via store, and the library AppBar `IconButton(icon: Icons.settings)` pushing `SettingsPage`.

- [ ] **Step 4: PASS** — also run `flutter test test/features/library_page_test.dart`.

- [ ] **Step 5: Commit** `feat: add model settings page with connection test`

---

### Task 4: OpenAI-compatible AssistantService

**Files:**
- Create: `lib/assistant/openai_assistant_service.dart`
- Create: `test/support/fake_llm_client.dart`
- Test: `test/assistant/openai_assistant_service_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class OpenAiAssistantService implements AssistantService {
    OpenAiAssistantService({required LlmClient client});
    // translate/explain/summarizeChapter/chat implemented on top of client.streamChat
  }
  ```
- Prompt rules: system message = 「你是阅读助手…」+ optional `context.bookBrief` preamble + `context.bookTitle/author/chapterTitle`; `chapterText` appended verbatim; `selectedText` for translate/explain; history mapped to `LlmMessage`s. `isConfigured` delegates to `LlmConfig Function()` → `config().isConfigured`; if not configured, methods throw `AssistantNotConfiguredException`.

- [ ] **Step 1: Failing tests** — fake client records messages: `chat` sends history then user message, includes chapter text; `summarizeChapter` prompt contains 「总结」 and chapter title; unconfigured throws `AssistantNotConfiguredException`.

- [ ] **Step 2: FAIL** — `flutter test test/assistant/openai_assistant_service_test.dart`.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: PASS.**

- [ ] **Step 5: Commit** `feat: implement assistant service over openai client`

---

### Task 5: Distill tables, migration, repositories

**Files:**
- Modify: `lib/data/db/tables.dart` (three tables), `lib/data/db/app_database.dart` (register + schemaVersion 5 + `if (from < 5) createTable…`)
- Create: `lib/data/repositories/distill_job_repository.dart`, `lib/data/repositories/distill_unit_repository.dart`, `lib/data/repositories/distill_artifact_repository.dart`
- Create: `lib/domain/models/distill.dart` (`DistillJob`, `DistillUnit`, `DistillArtifact`, `DistillStatus`, `DistillStage`, `DistillArtifactKind`)
- Modify: `lib/domain/services/book_service.dart` (`deleteBook` also clears distill rows)
- Test: `test/data/distill_repository_test.dart`

**Interfaces:**
- Tables (drift):
  ```
  DistillJobs: id TEXT PK, bookId TEXT, contentHash TEXT, status TEXT, stage TEXT,
    pipelineVersion INT, totalUnits INT, doneUnits INT, errorText TEXT?, createdAt, updatedAt
  DistillUnits: id TEXT PK, jobId TEXT, unitKey TEXT, kind TEXT, status TEXT,
    resultJson TEXT?, attempts INT, updatedAt
  DistillArtifacts: id TEXT PK, bookId TEXT, kind TEXT, unitKey TEXT, title TEXT,
    body TEXT, dataJson TEXT, chapterStart INT?, chapterEnd INT?, stale BOOL, createdAt
  ```
  Unique index on `(jobId, unitKey)`; index `(bookId, kind)`.
- Produces:
  ```dart
  class DistillJobRepository {
    Future<DistillJob?> getByBook(String bookId);
    Future<void> save(DistillJob job);
    Future<void> deleteForBook(String bookId);
  }
  class DistillUnitRepository {
    Future<void> put(DistillUnit unit);
    Future<Set<String>> doneKeys(String jobId);
    Future<void> deleteForJob(String jobId);
    Future<void> deleteForBook(String bookId);   // via job ids
  }
  class DistillArtifactRepository {
    Future<void> put(DistillArtifact artifact);
    Future<List<DistillArtifact>> listByBook(String bookId, {DistillArtifactKind? kind});
    Future<void> markStale(String bookId);
    Future<void> deleteForBook(String bookId);
  }
  ```
- `BookService.deleteBook` gains `await jobs.deleteForBook(book.id)` (inject a `DistillJobRepository?` optional constructor param defaulting to null; when null skip) — avoids breaking existing construction sites.

- [ ] **Step 1: Failing tests** — memory db: insert job/unit/artifact, `doneKeys` returns set, duplicate `(jobId, unitKey)` upserts not throws, `deleteBook` removes rows, `markStale` flips flag.

- [ ] **Step 2: FAIL** — `flutter test test/data/distill_repository_test.dart`.

- [ ] **Step 3: Implement** tables + migration + repositories; run `dart run build_runner build --delete-conflicting-outputs` to regenerate `app_database.g.dart`.

- [ ] **Step 4: PASS** + `flutter test test/data/book_service_test.dart`.

- [ ] **Step 5: Commit** `feat: add distill persistence tables and repositories`

---

### Task 6: Segment planner

**Files:**
- Create: `lib/distill/distill_planner.dart`
- Test: `test/distill/distill_planner_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class DistillSegment { final String key; final int chapterIndex; final String chapterTitle;
    final int charStartInChapter; final int charEndInChapter; final String text; }
  class DistillPart { final String key; final List<DistillSegment> segments; final List<int> chapterIndexes; }
  class DistillPlan { final List<DistillSegment> segments; final List<DistillPart> parts; }
  class DistillPlanner {
    DistillPlanner({this.maxSegmentChars = 6000, this.maxPartChars = 60000, this.minChaptersPerPart = 2});
    DistillPlan plan(List<Chapter> chapters);
  }
  ```

- [ ] **Step 1: Failing tests** — a 15k-char chapter yields 3 segments each ≤6000, boundaries at the last `\n` before the limit, none crossing into the next chapter; a one-chapter book yields ≥2 segments; parts never exceed `maxPartChars` and never group a single chapter alone when a neighbour is available; empty chapters are skipped and `key` stays contiguous (`seg-0000`…).

- [ ] **Step 2: FAIL** — `flutter test test/distill/distill_planner_test.dart`.

- [ ] **Step 3: Implement**: per chapter, if `contentText.length <= maxSegmentChars` emit one segment; else walk forward, cut at the last `\n` in `(start, start+maxSegmentChars]` (fallback: hard cut), trim leading whitespace, skip zero-length. Parts: accumulate segments until adding the next chapter would exceed `maxPartChars` (respect `minChaptersPerPart` by merging two undersized parts).

- [ ] **Step 4: PASS.**

- [ ] **Step 5: Commit** `feat: add distill segment and part planner`

---

### Task 7: Distill prompts, JSON parsing, quote verification

**Files:**
- Create: `lib/distill/distill_prompts.dart`, `lib/distill/distill_models.dart`, `lib/distill/quote_verifier.dart`
- Test: `test/distill/distill_models_test.dart`, `test/distill/quote_verifier_test.dart`

**Interfaces:**
- Produces:
  ```dart
  // prompts: pure functions returning List<LlmMessage>
  List<LlmMessage> mapPrompt(DistillSegment segment, {required String bookTitle, String? previousGist});
  List<LlmMessage> reducePartPrompt(DistillPart part, {required String bookTitle});
  List<LlmMessage> overviewPrompt(List<String> partSummaries, {required String bookTitle, required String author});
  List<LlmMessage> cardsPrompt(List<String> candidates, {required String bookTitle});
  List<LlmMessage> verifyPrompt(String cardJson, String sourceText);

  class MapResult { final List<String> points; final List<String> entities; final List<String> toneCues; final List<String> quotes; }
  class PartResult { final String summary; final List<ChapterGist> chapters; }
  class ChapterGist { final int chapterIndex; final String title; final String gist; }
  class BookOverview { final String oneLiner; final String synopsis; final List<String> themes; final List<ThemeArc> structure; final String argument; }
  class ToneProfile { final String overall; final String narrator; final List<ToneArc> arc; final List<String> style; final List<String> sampleQuotes; }
  class DistillCard { final String slug; final String title; final String type; final String definition; final List<int> sourceChapters; final String? quote; }

  MapResult parseMapResult(String raw);          // tolerates ```json fences, throws DistillParseException
  PartResult parsePartResult(String raw);
  BookOverview parseOverview(String raw);
  ToneProfile parseTone(String raw);
  List<DistillCard> parseCards(String raw);

  class QuoteVerifier {
    QuoteVerifier(String bookText);              // whitespace-collapsed index
    bool contains(String quote);                 // >150 chars → false
  }
  ```
- System prompt (shared constant) enforces: Chinese output, strict JSON only, quotes ≤150 chars verbatim from input, no content beyond the supplied text.

- [ ] **Step 1: Failing tests** — fenced JSON parses; missing `points` defaults to `[]`; malformed JSON throws `DistillParseException`; quote found across newlines matches; 200-char quote rejected; cards with unknown `sourceChapters` are kept but flagged by pipeline (assert parse keeps them).

- [ ] **Step 2: FAIL** — the two test files.

- [ ] **Step 3: Implement**, normalising whitespace and `\u3000` before substring search.

- [ ] **Step 4: PASS.**

- [ ] **Step 5: Commit** `feat: add distill prompts and json parsers`

---

### Task 8: Pipeline orchestrator with resume and cancel

**Files:**
- Create: `lib/distill/distill_pipeline.dart`
- Test: `test/distill/distill_pipeline_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class DistillProgress { final DistillStage stage; final int doneUnits; final int totalUnits; final String? currentUnit; }
  class DistillPipeline {
    DistillPipeline({required String bookId, required String contentHash, required List<Chapter> chapters,
      required LlmClient client, required DistillPlanner planner,
      required DistillJobRepository jobs, required DistillUnitRepository units,
      required DistillArtifactRepository artifacts, int pipelineVersion = 1, int concurrency = 3});
    Future<void> run({void Function(DistillProgress)? onProgress, CancelToken? cancel});
  }
  ```
- Behaviour: creates or resumes the job (`contentHash` mismatch or `pipelineVersion` mismatch → mark artifacts stale, reset units), plans segments/parts, runs map with concurrency 3, then reduce-1 per part, reduce-2, cards (batches of 20 candidates), verify (quotes + `sourceChapters`), writes artifacts, sets `done`. Each unit persisted on completion. On `cancel.isCanceled` stop before issuing new calls and set `canceled`. On `DistillParseException`/`LlmException`: one retry with a repair message, then `failed` unit + job `paused`.

- [ ] **Step 1: Failing tests** (fake client returns canned JSON keyed by the first 20 chars of the system prompt):
  - small 3-chapter book: artifacts = 1 overview, 3 gists, ≥1 card, 1 tone; job `done`; calls ≤80
  - resume: pre-insert done units for half the segments, rerun, assert only missing units call the client
  - cancel after 1 unit: job `canceled`, no further client calls
  - bad JSON twice: unit `failed`, job `paused`, `errorText` non-null
  - one-chapter 15k book: segments ≥2, still `done`

- [ ] **Step 2: FAIL** — `flutter test test/distill/distill_pipeline_test.dart`.

- [ ] **Step 3: Implement** a sequential stage runner with a `for` over items and a `Semaphore(3)`-style helper (no new deps: a `Future` queue class inside the file).

- [ ] **Step 4: PASS.**

- [ ] **Step 5: Commit** `feat: add resumable distill pipeline`

---

### Task 9: Distill controller and distill page

**Files:**
- Create: `lib/features/distill/distill_controller.dart`, `lib/features/distill/distill_page.dart`
- Modify: `lib/features/library/book_card.dart` (menu entry), `lib/main.dart` (lifecycle observer for pause)
- Test: `test/features/distill_page_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class DistillState { final DistillJob? job; final DistillProgress? progress; final String? error; final bool isRunning; }
  class DistillController extends Notifier<DistillState> {
    DistillController(this.bookId);
    void start(); void resume(); void pause(); void cancel();   // pause sets a flag the loop checks, cancel uses CancelToken
  }
  final distillControllerProvider = NotifierProvider.family<DistillController, DistillState, String>(DistillController.new);
  ```
- `DistillPage` (route arg `bookId`): progress bar `doneUnits/totalUnits`, stage label, 暂停/继续/取消, error text, and after `done` four tabs: 总览 / 章节地图 / 卡片 / 语气 (rendered from artifacts; plain `Text` + `ListView`, no markdown package).

- [ ] **Step 1: Failing widget tests** with `distillControllerProvider` overridden by a fake state: renders progress text 「12 / 47」, pause button toggles label, error shows message, done shows tabs.

- [ ] **Step 2: FAIL** — `flutter test test/features/distill_page_test.dart`.

- [ ] **Step 3: Implement**; call `ref.keepAlive()` inside `build`, start the pipeline in a detached `Future` guarded by `isRunning`, listen to `AppLifecycleState.paused` to set the pause flag. Book card: `PopupMenuButton` with 「蒸馏」 (disabled + tooltip for PDF/no-chapters) opening `DistillPage`.

- [ ] **Step 4: PASS** + `flutter test test/features/library_page_test.dart`.

- [ ] **Step 5: Commit** `feat: add distill page and job controller`

---

### Task 10: Context assembler, ReadingContext fields, decorator service

**Files:**
- Modify: `lib/assistant/reading_context.dart` (add `bookId`, `chapterIndex`, `chapterCharOffset`, `bookBrief`)
- Create: `lib/distill/distilled_context_assembler.dart`, `lib/distill/distill_digest.dart`
- Create: `lib/assistant/digest_aware_assistant_service.dart`
- Modify: `lib/app/providers.dart` (assistant service composition)
- Test: `test/distill/distilled_context_assembler_test.dart`, `test/assistant/digest_aware_assistant_service_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class AssembleInput { final String bookId, bookTitle, author, chapterTitle, chapterText, question; final int chapterIndex; final int? chapterCharOffset; }
  class AssembledContext { final String brief; final int usedChars; }
  class DistilledContextAssembler {
    DistilledContextAssembler({this.maxBriefChars = 1200, this.maxToneChars = 300, this.maxChapterChars = 4000,
      this.maxGistChars = 60, this.maxCards = 3, this.cardChars = 250});
    AssembledContext assemble(AssembleInput input, DistillDigest digest);
  }
  String windowedExcerpt(String text, {int? charOffset, int head = 800, int around = 2400, int tail = 800});
  abstract class DistillDigestSource { Future<DistillDigest?> load(String bookId); }
  class DigestAwareAssistantService implements AssistantService {
    DigestAwareAssistantService({required AssistantService inner, required DistillDigestSource source});
  }
  ```
- Card scoring: `3 × term overlap + 2 × (sourceChapters contains chapterIndex) + 1 × bigram overlap with question`; tie-break by lower `sourceChapters.first`, then slug. Degradation: no digest → pass through; incomplete → use what exists; over budget → drop far cards, then neighbour gists.
- `assistantServiceProvider` becomes `FutureProvider<AssistantService>`: unconfigured → `UnconfiguredAssistantService`, else `DigestAwareAssistantService(inner: OpenAiAssistantService(client), source: repoSource)`.

- [ ] **Step 1: Failing tests**
  - `windowedExcerpt` at 90% of a 20k chapter contains text from the anchor ±500 and stays ≤4000
  - assembler includes overview one-liner, tone, current chapter window, neighbour gists, top-3 cards; total ≤ `maxBriefChars + 300 + 4000`
  - no digest → `brief` equals plain chapter excerpt (decorator passes `ReadingContext` through unchanged)
  - spoiler guard string contains 「第 3 章」 and 「不要引用后面章节」
  - decorator: fake inner service receives `bookBrief` non-empty and unchanged `chapterText` for `chat`

- [ ] **Step 2: FAIL** — both test files.

- [ ] **Step 3: Implement** (pure functions; digest parsed from artifacts).

- [ ] **Step 4: PASS** + `flutter test test/assistant/reading_context_builder_test.dart`.

- [ ] **Step 5: Commit** `feat: assemble distilled context for companion chat`

---

### Task 11: Companion panel in the reader

**Files:**
- Create: `lib/features/companion/companion_panel.dart`
- Modify: `lib/features/reader/reader_page.dart` (AppBar 陪读 icon; chapter summary button)
- Test: `test/features/companion_panel_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class CompanionPanel extends ConsumerStatefulWidget {
    const CompanionPanel({super.key, required this.bookId, required this.chapterIndex,
      required this.chapterTitle, required this.chapterText, required this.chapterCharOffset});
  }
  ```
- Panel: `showModalBottomSheet(isScrollControlled: true)`; message list + input; 「总结本章」 button calls `summarizeChapter`; unconfigured → 「未配置 AI 服务，请到设置页填写」 with a button to `SettingsPage`; in-memory history per panel instance.

- [ ] **Step 1: Failing widget tests** — unconfigured panel shows the settings prompt; with a fake `AssistantService` chat text appears; summary button streams into the panel.

- [ ] **Step 2: FAIL** — `flutter test test/features/companion_panel_test.dart`.

- [ ] **Step 3: Implement**; `ReaderPage` computes `chapterCharOffset` from `_currentProgress()?.anchor.charOffset - currentChapter.startOffset` (clamped ≥0) and passes it in.

- [ ] **Step 4: PASS** + `flutter test test/features/reader_page_test.dart`.

- [ ] **Step 5: Commit** `feat: add companion chat panel to reader`

---

### Task 12: Stale detection, docs, and branch wrap-up

**Files:**
- Modify: `lib/features/distill/distill_controller.dart` (re-hash on start, compare `contentHash`/`pipelineVersion`, mark stale, show 「书籍内容已变化，需要重新蒸馏」)
- Modify: `CONTRIBUTING.md` (feature list + test counts), `docs/superpowers/specs/2026-11-03-book-distillation-design.md` (mark implemented decisions)
- Test: `test/features/distill_controller_test.dart`

**Interfaces:** consumes Task 5/9 APIs; no new production types.

- [ ] **Step 1: Failing test** — controller with a fake pipeline and a changed hash: `start()` sets artifacts stale and does not call the pipeline until the user confirms; with matching hash it calls.

- [ ] **Step 2: FAIL** — `flutter test test/features/distill_controller_test.dart`.

- [ ] **Step 3: Implement** hash comparison (`sha256` over `File(book.sourcePath)`), update docs.

- [ ] **Step 4: Full suite** — `flutter test` (all files) and `flutter analyze` clean.

- [ ] **Step 5: Commit** `feat: guard distill artifacts against stale content` and open the branch summary.

---

## Self-Review Notes

- **Spec coverage:** §9 pipeline → Tasks 6–8; §10 assembly → Task 10–11; §11 tables → Task 5; §12 client → Tasks 1–2, 4; §13 UI → Tasks 3, 9, 11; §14 errors → Tasks 2, 8, 12; §19 decisions (PDF off, segments, no signature change, windowing, ≤80 calls, in-memory chat) → Tasks 3, 6, 10, 11, Global Constraints.
- **Out of scope by decision:** PDF distillation, `translate`/`explain` UI, markdown/skill export, chat persistence, secure-storage key, file watchers.
- **Type consistency:** `DistillProgress` used by Task 8 controller (Task 9) and page; `DistillDigest` produced in Task 10 from Task 5 artifacts; `unitKey` format fixed in Global Constraints and Task 6 (`seg-%04d`).
