# Reader App Phase 1 (M0–M3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A runnable Flutter app for Windows and Android that imports EPUB/TXT/PDF into a local library and lets the user read TXT books with auto-detected chapters, a jumpable TOC, adjustable text display, and restored reading position.

**Architecture:** Flutter + Riverpod for UI/DI, Drift/SQLite for local data. Import copies the source file into app storage and records metadata. TXT decoding and chapter detection are pure Dart services behind small interfaces, unit-tested without Flutter. The reader shows one chapter at a time in a scrolling view and stores progress as a book-global character offset.

**Tech Stack:** Flutter (stable, Dart 3), flutter_riverpod, drift/drift_flutter, path_provider, file_picker, uuid, charset_codec, path, flutter_test, drift_dev + build_runner.

**Spec:** `docs/superpowers/specs/2026-11-03-reader-app-design.md`

## Global Constraints

- Targets: Windows 10/11 and Android only. No iOS/macOS deliverable. Flutter Web is not part of this plan.
- Project/package name: `hackathon_reading`; org: `com.icetea`.
- UI language: Chinese. Material 3.
- Core features must work fully offline. No network calls in this phase.
- Books are copied into `<application support dir>/books/<uuid>.<ext>`; the original file may move afterwards.
- SQLite via Drift; IDs are UUID v4 strings.
- Limits: TXT/EPUB ≤ 50 MB or ≤ 2000 chapters; PDF ≤ 1000 pages; library ≤ 500 books.
- No real AI calls, no OCR, no PDF annotations, no EPUB/PDF chapter parsing in this phase.
- Every task ends with `flutter analyze` clean and `flutter test` green, then one commit on `develop`.
- Do not commit build artifacts, local databases, `.claude/`, or user test books.
- Windows desktop builds require Visual Studio 2022 with the "Desktop development with C++" workload. Windows Developer Mode is only needed later for `pdfrx` (M5), not for this plan.

## Review Focus

1. **Chinese TXT encodings** — UTF-8, UTF-8 BOM, UTF-16 LE/BE, GBK/GB18030 files must decode without mojibake; unknown bytes must degrade, not crash.
2. **Chapter false positives** — a prose line starting with "第一章…" must not become a chapter heading; no text may be dropped when chapters are split.
3. **Large TXT files** — a multi-megabyte, thousands-of-chapters book must import and open without freezing or producing wrong boundaries.
4. **Awkward file names/contents** — uppercase extensions, Chinese names, spaces, zero-byte or corrupt files must succeed or fail with a clear error and leave no half-imported book.
5. **Progress restoration** — after restart, font-size change, or window resize, reopening a book must land in the same passage, not the wrong chapter.

---

### Task 1: Project scaffold and app shell (M0 + M1)

**Files:**
- Create: `pubspec.yaml` (via `flutter create` + `flutter pub add`)
- Create: `lib/main.dart`
- Create: `lib/app/app.dart`
- Create: `lib/app/theme/app_theme.dart`
- Create: `lib/features/library/library_page.dart`
- Modify: `README.md`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `void main()` — runs `ProviderScope(child: BookApp())`.
  - `class BookApp extends StatelessWidget` — `MaterialApp(title: 'AI 阅读器', theme: AppTheme.light, darkTheme: AppTheme.dark, home: const LibraryPage())`.
  - `class AppTheme` — static `ThemeData light` and `dark`, Material 3, seed color `Color(0xFF4F6BED)`.
  - `class LibraryPage extends StatelessWidget` — AppBar title `书架`, empty state text `还没有书，点右上角导入`.

- [ ] **Step 1: Install and verify the toolchain**

Install Flutter stable on Windows (official Windows installer), then Android Studio with an SDK and one emulator. Ensure Visual Studio 2022 has the "Desktop development with C++" workload.

Run:
```bash
flutter --version
flutter doctor -v
```
Expected: Flutter stable 3.x is reported; Flutter, Windows, and Android toolchain sections show no blocking errors. If Windows or Android toolchain fails, fix it before continuing.

- [ ] **Step 2: Create the Flutter project in place**

Run:
```bash
flutter create --org com.icetea --project-name hackathon_reading --platforms=windows,android .
```
Expected: `android/`, `windows/`, and `lib/main.dart` exist. Delete the generated `test/widget_test.dart` (it targets the counter demo).

- [ ] **Step 3: Add dependencies**

Run:
```bash
flutter pub add flutter_riverpod drift drift_flutter path_provider file_picker uuid charset_codec path
flutter pub add dev:drift_dev dev:build_runner
```
Expected: `pubspec.yaml` lists all packages; `flutter pub get` succeeds.

- [ ] **Step 4: Write the failing widget test**

Create `test/app/app_shell_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hackathon_reading/app/app.dart';

void main() {
  testWidgets('shows the empty library shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BookApp()));
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('还没有书，点右上角导入'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `flutter test test/app/app_shell_test.dart`
Expected: FAIL because `package:hackathon_reading/app/app.dart` does not exist.

- [ ] **Step 6: Implement the shell and theme**

Create the files listed above. `LibraryPage` is a plain `StatelessWidget` at this stage (no database). In `main.dart`, call `WidgetsFlutterBinding.ensureInitialized()` then `runApp(const ProviderScope(child: BookApp()))`.

- [ ] **Step 7: Verify**

Run:
```bash
flutter analyze
flutter test
```
Expected: no analyzer issues; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib test README.md android windows .gitignore .metadata analysis_options.yaml
git commit -m "feat: scaffold Flutter app with Chinese library shell"
```

---

### Task 2: Book model, Books table, and repository (M2)

**Files:**
- Create: `lib/domain/models/book.dart`
- Create: `lib/data/db/tables.dart`
- Create: `lib/data/db/app_database.dart`
- Create: `lib/data/repositories/book_repository.dart`
- Test: `test/data/book_repository_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum BookFormat { epub, txt, pdf }` with `String get extension` and `static BookFormat? fromExtension(String pathOrName)` (case-insensitive; returns `null` when unsupported).
  - `class Book` — fields `String id`, `String title`, `String author`, `BookFormat format`, `String sourcePath`, `String? coverPath`, `DateTime addedAt`, `DateTime? lastOpenedAt`.
  - Drift tables: `Books` (`@DataClassName('BookRow')`, PK `id`), `Chapters` (`@DataClassName('ChapterRecord')`, PK `id`), `ReadingProgressEntries` (`@DataClassName('ProgressRow')`, PK `bookId`). Create only `Books` now; the other two tables are added in Task 7.
  - `class AppDatabase extends _$AppDatabase` — `AppDatabase(QueryExecutor e)` for tests; `AppDatabase.defaults()` uses `driftDatabase(name: 'reader')`; `schemaVersion => 1`.
  - `class BookRepository` — `Stream<List<Book>> watchAll()`, `Future<List<Book>> getAll()`, `Future<Book?> getById(String id)`, `Future<void> upsert(Book book)`, `Future<void> delete(String id)`.
- Ordering for `watchAll`/`getAll`: `addedAt` descending.

- [ ] **Step 1: Write the failing repository test**

Create `test/data/book_repository_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late BookRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BookRepository(db);
  });
  tearDown(() => db.close());

  Book sample(String id) => Book(
        id: id,
        title: '测试书',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/$id.txt',
        addedAt: DateTime(2026, 1, 1),
      );

  test('inserts, lists, and deletes books', () async {
    await repo.upsert(sample('b1'));
    expect((await repo.getAll()).single.title, '测试书');
    await repo.delete('b1');
    expect(await repo.getAll(), isEmpty);
  });

  test('orders by addedAt descending', () async {
    await repo.upsert(sample('old'));
    await repo.upsert(Book(
      id: 'new',
      title: '新书',
      author: '',
      format: BookFormat.epub,
      sourcePath: 'C:/books/new.epub',
      addedAt: DateTime(2026, 2, 1),
    ));
    expect((await repo.getAll()).map((b) => b.id), ['new', 'old']);
  });

  test('parses extensions case-insensitively', () {
    expect(BookFormat.fromExtension('A.TXT'), BookFormat.txt);
    expect(BookFormat.fromExtension('book.epub'), BookFormat.epub);
    expect(BookFormat.fromExtension('x.doc'), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/book_repository_test.dart`
Expected: FAIL because the database and repository files do not exist.

- [ ] **Step 3: Implement the model, tables, database, and repository**

Map Drift rows to domain `Book` in the repository. Store `format` as `format.name`. Run code generation:
```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/book_repository_test.dart`
Expected: PASS. If SQLite cannot be loaded under `flutter test`, add the drift-recommended `flutter_test_config.dart` for the local platform before continuing; do not skip the test.

- [ ] **Step 5: Commit**

```bash
git add lib/domain lib/data test/data
git commit -m "feat: add book model and Drift-backed book repository"
```

---

### Task 3: File storage and book import service (M2)

**Files:**
- Create: `lib/data/storage/book_storage.dart`
- Create: `lib/domain/services/book_service.dart`
- Test: `test/domain/book_service_test.dart`

**Interfaces:**
- Consumes: `Book`, `BookFormat`, `BookRepository` from Task 2.
- Produces:
  - `class BookStorage` — `BookStorage(Directory booksRoot)`; `Future<String> copyIn(String sourcePath, String id, BookFormat format)` copies to `<root>/<id>.<ext>` and returns the new path; `Future<void> deleteFile(String path)` (no-op if missing).
  - `class BookService` — `BookService({required BookRepository books, required BookStorage storage, String Function()? newId})`; `Future<Book> importFile(String sourcePath)`.
  - Import behavior: validate extension (case-insensitive) and non-empty file; derive title from filename without extension; `author = ''`; copy first, insert second; on insert failure delete the copy; unsupported format throws `UnsupportedBookFormatException`; empty file throws `EmptyBookException`; unreadable path propagates `FileSystemException`.
  - `Future<void> deleteBook(Book book)` — deletes the DB row and copied file (chapter/progress cleanup added in Task 7).

- [ ] **Step 1: Write the failing tests**

Create `test/domain/book_service_test.dart` with a temp directory and in-memory database. Cover:
```dart
test('imports an uppercase TXT with a Chinese name', () async {
  final source = File('${temp.path}/我的 小说.TXT')
    ..writeAsStringSync('第一章 开始\n内容');
  final book = await service.importFile(source.path);
  expect(book.format, BookFormat.txt);
  expect(book.title, '我的 小说');
  expect(File(book.sourcePath).readAsStringSync(), contains('第一章'));
  expect((await repo.getAll()).single.id, book.id);
});

test('rejects unsupported extensions without recording a book', () async {
  final source = File('${temp.path}/a.doc')..writeAsStringSync('x');
  await expectLater(service.importFile(source.path),
      throwsA(isA<UnsupportedBookFormatException>()));
  expect(await repo.getAll(), isEmpty);
});

test('rejects empty files without recording a book', () async {
  final source = File('${temp.path}/empty.txt')..writeAsBytesSync([]);
  await expectLater(service.importFile(source.path),
      throwsA(isA<EmptyBookException>()));
  expect(await repo.getAll(), isEmpty);
});

test('delete removes the copied file and the record', () async { /* ... */ });
```
Inject `newId: () => 'fixed-id'` for deterministic paths.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/domain/book_service_test.dart`
Expected: FAIL because `BookStorage` and `BookService` do not exist.

- [ ] **Step 3: Implement `BookStorage` and `BookService`**

Create the books root lazily with `create(recursive: true)`. Use `p.basenameWithoutExtension` for the title and `p.extension` for the format check. For now, `deleteBook` only removes the book row and its copied file.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/domain/book_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/storage lib/domain/services test/domain
git commit -m "feat: import books into managed storage with validation"
```

---

### Task 4: Library UI wired to import and delete (M2)

**Files:**
- Create: `lib/app/providers.dart`
- Create: `lib/features/library/book_card.dart`
- Create: `lib/domain/services/file_picker_service.dart`
- Modify: `lib/features/library/library_page.dart`
- Test: `test/features/library_page_test.dart`

**Interfaces:**
- Consumes: `BookService`, `BookRepository`, `BookStorage`; `Book`.
- Produces:
  - `abstract class FilePickerService { Future<String?> pickBookFile(); }` — implementation uses `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['epub','txt','pdf'])` and returns `result?.files.single.path`.
  - Riverpod providers in `lib/app/providers.dart`: `appDatabaseProvider`, `bookRepositoryProvider`, `bookStorageProvider` (default root `<application support>/books`), `bookServiceProvider`, `filePickerProvider`, `bookListProvider` (`StreamProvider<List<Book>>` watching `watchAll()`).
  - `LibraryPage` — import button in the AppBar; `GridView` of `BookCard`; empty state from Task 1; errors shown via `SnackBar` with the exception message.
  - `BookCard` — title, format label, cover placeholder; tapping a TXT book with no chapters yet shows `SnackBar('阅读器将在下一步实现')`; tapping other formats shows `SnackBar('该格式将在后续里程碑支持')`; a delete action asks for confirmation, then calls `deleteBook`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/library_page_test.dart`. Override `appDatabaseProvider` with `AppDatabase(NativeDatabase.memory())`, `bookStorageProvider` with a temp directory, and `filePickerProvider` with a fake returning a generated TXT path. Tests:
1. empty state appears initially;
2. tapping import adds a card with the file's title;
3. tapping delete and confirming removes the card and the copied file;
4. an unsupported-picker error is surfaced in a SnackBar.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/library_page_test.dart`
Expected: FAIL because the providers and new UI do not exist.

- [ ] **Step 3: Implement the providers, picker abstraction, card, and page**

Use `ConsumerWidget`/`ConsumerStatefulWidget`. Use `ref.listen` or `try/catch` around import to show SnackBars. Do not block the UI thread with file copying beyond normal async I/O.

- [ ] **Step 4: Verify**

Run:
```bash
flutter analyze
flutter test
flutter run -d windows
```
Expected: analyze clean; tests pass; on Windows the app opens, the picker can import a TXT, and the card appears.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat: wire library UI to import and delete"
```

---

### Task 5: TXT encoding detection (M3)

**Files:**
- Create: `lib/domain/models/decoded_text.dart`
- Create: `lib/domain/services/txt_decoder.dart`
- Test: `test/domain/txt_decoder_test.dart`

**Interfaces:**
- Consumes: `charset_codec` package.
- Produces:
  - `class DecodedText { final String text; final String encoding; }`
  - `DecodedText decodeTxtBytes(List<int> bytes)`.
  - Detection order: UTF-8 BOM → UTF-16 LE/BE BOM (decode 16-bit code units) → strict UTF-8 → strict GB18030 via `tryDecodeBytes` → lossy UTF-8 (`utf8.decode(bytes, allowMalformed: true)`, encoding label `utf-8-lossy`).
  - Empty input returns `DecodedText('', 'utf-8')`.

- [ ] **Step 1: Write the failing tests**

Create `test/domain/txt_decoder_test.dart` covering:
```dart
test('decodes UTF-8 Chinese', () { ... });
test('decodes UTF-8 with BOM', () {
  final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('中文')];
  final result = decodeTxtBytes(bytes);
  expect(result.text, '中文');
  expect(result.encoding, 'utf-8');
});
test('decodes UTF-16 LE with BOM', () { /* FF FE + code units */ });
test('decodes GB18030 Chinese', () {
  final bytes = encodeString('第一章 开始', encoding: 'gb18030');
  final result = decodeTxtBytes(bytes);
  expect(result.text, '第一章 开始');
  expect(result.encoding, 'gb18030');
});
test('never throws on invalid bytes', () {
  final result = decodeTxtBytes([0xFF, 0xFF, 0x00, 0xD8]);
  expect(result.encoding, 'utf-8-lossy');
});
test('empty input', () { ... });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/domain/txt_decoder_test.dart`
Expected: FAIL because `decodeTxtBytes` does not exist.

- [ ] **Step 3: Implement the decoder**

For UTF-16, read the BOM, build 16-bit code units with `ByteData` in the matching endianness, and use `String.fromCharCodes`. Treat a lone BOM-only file as empty text.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/domain/txt_decoder_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat: detect TXT encoding with GB18030 and UTF-16 support"
```

---

### Task 6: TXT chapter detection (M3)

**Files:**
- Create: `lib/domain/models/detected_chapter.dart`
- Create: `lib/domain/services/txt_chapter_detector.dart`
- Test: `test/domain/txt_chapter_detector_test.dart`

**Interfaces:**
- Consumes: decoded text (plain `String`).
- Produces:
  - `class DetectedChapter { final String title; final int startOffset; final int endOffset; }`
  - `List<DetectedChapter> detectTxtChapters(String text, {String fallbackTitle = '正文'})`.
  - Rules:
    - Scan line by line, preserving absolute offsets; strip a trailing `\r` from the matched line only.
    - A heading line: trimmed length 1–40, starts at the beginning of the line after optional whitespace, does not end with `。！？；`, and matches one of:
      - `^第[0-9０-９一二三四五六七八九十百千万零两〇]+[章节卷回部篇集](?:\s|[:：、.．\-—]|$)`
      - `^(?:序章|楔子|引子|前言|序言|后记|尾声|番外|正文)(?:\s|[:：、.．\-—]|$)`
      - `^Chapter\s+[0-9IVXLC]+(?:\s|[:：.\-]|$)` (case-insensitive)
    - Text before the first heading: if it has any non-whitespace, emit a `前言` chapter covering `[0, firstHeadingStart)`; otherwise start the first chapter at the heading.
    - No headings: return one chapter `[0, text.length)` titled `fallbackTitle`.
    - Empty/whitespace-only text: return an empty list.
    - Each chapter ends where the next begins; the last ends at `text.length`. Never drop characters between chapters.

- [ ] **Step 1: Write the failing tests**

Create `test/domain/txt_chapter_detector_test.dart` covering:
```dart
test('detects Chinese and English headings with exact offsets', () { ... });
test('creates a 前言 chapter for leading text', () { ... });
test('returns a single fallback chapter when no headings exist', () { ... });
test('does not treat long prose starting with 第一章 as a heading', () {
  const text = '第一章就写到了主角的童年，这部分内容很长，而且是一句完整的话。\n第二段';
  final chapters = detectTxtChapters(text);
  expect(chapters.single.title, '正文');
  expect(chapters.single.startOffset, 0);
  expect(chapters.single.endOffset, text.length);
});
test('handles CRLF without shifting offsets', () { ... });
test('detects 番外 and 第123章 headings', () { ... });
test('handles 2000 chapters without losing content', () {
  final buffer = StringBuffer();
  for (var i = 1; i <= 2000; i++) {
    buffer.writeln('第$i章 标题$i');
    buffer.writeln('正文$i');
  }
  final text = buffer.toString();
  final chapters = detectTxtChapters(text);
  expect(chapters, hasLength(2000));
  expect(chapters.first.startOffset, 0);
  expect(chapters.last.endOffset, text.length);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/domain/txt_chapter_detector_test.dart`
Expected: FAIL because `detectTxtChapters` does not exist.

- [ ] **Step 3: Implement the detector**

Split on `\n`, keep a running offset, and match the trimmed line without changing offsets. Add `text.length` for each line's newline. Use a single compiled `RegExp` with alternation for the three heading forms.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/domain/txt_chapter_detector_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat: detect TXT chapters with Chinese heading heuristics"
```

---

### Task 7: Chapter/progress storage and TXT import pipeline (M3)

**Files:**
- Modify: `lib/data/db/tables.dart` (add `Chapters`, `ReadingProgressEntries`)
- Modify: `lib/data/db/app_database.dart` (schema version 2 + migration)
- Create: `lib/data/repositories/chapter_repository.dart`
- Create: `lib/data/repositories/progress_repository.dart`
- Create: `lib/domain/models/chapter.dart`
- Create: `lib/domain/models/reading_progress.dart`
- Create: `lib/domain/services/txt_book_parser.dart`
- Modify: `lib/domain/services/book_service.dart` (parse TXT, cascade delete)
- Test: `test/domain/txt_import_test.dart`

**Interfaces:**
- Consumes: Task 5 `DecodedText`, Task 6 `detectTxtChapters`, Task 3 `BookService`.
- Produces:
  - `class Chapter` — `String id`, `String bookId`, `int index`, `String title`, `int startOffset`, `int endOffset`, `String contentText`.
  - `class ReadingAnchor { final int charOffset; Map<String, dynamic> toJson(); factory ReadingAnchor.fromJson(Map<String, dynamic> json); }`
  - `class ReadingProgress { final String bookId; final ReadingAnchor anchor; final double percent; final DateTime updatedAt; }`
  - `Chapters` table: `id` PK, `bookId`, `index` (column name `chapter_index` to avoid SQL keyword), `title`, `startOffset`, `endOffset`, `contentText`. Index on `(bookId, chapter_index)`.
  - `ReadingProgressEntries` table: `bookId` PK, `anchorJson`, `percent`, `updatedAt`.
  - `ChapterRepository` — `Future<void> replaceForBook(String bookId, List<Chapter> chapters)`, `Future<List<Chapter>> getForBook(String bookId)`.
  - `ProgressRepository` — `Future<ReadingProgress?> get(String bookId)`, `Future<void> save(ReadingProgress progress)`.
  - `class TxtDocument { final String text; final String encoding; final List<DetectedChapter> chapters; }`; `TxtDocument parseTxtDocument(List<int> bytes, {required String fallbackTitle})`.
  - `BookService` gains dependencies: `BookService({required BookRepository books, required ChapterRepository chapters, required ProgressRepository progress, required BookStorage storage, String Function()? newId})`.
  - `BookService.importFile` for TXT: copy → parse → insert book → replace chapters. On any failure after copy, delete the copied file and the book row. `deleteBook` also deletes chapters and progress.

- [ ] **Step 1: Write the failing tests**

Create `test/domain/txt_import_test.dart` using an in-memory DB and temp storage:
1. UTF-8 TXT import stores chapters in order, with `contentText == original.substring(startOffset, endOffset)`.
2. GB18030 TXT import produces the same chapter titles as the UTF-8 equivalent.
3. TXT without headings stores exactly one chapter covering the whole file.
4. Progress save followed by get returns the same `charOffset`.
5. `deleteBook` removes the book, its chapters, its progress, and the copied file.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/domain/txt_import_test.dart`
Expected: FAIL because the tables and services do not exist.

- [ ] **Step 3: Implement schema v2, repositories, and parser**

Add the new tables and bump `schemaVersion` to 2. `onUpgrade` creates the two new tables when `from < 2`. Run:
```bash
dart run build_runner build --delete-conflicting-outputs
```
Implement `TxtBookParser` and extend `BookService`. Use a transaction for book + chapters insertion.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/domain/txt_import_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib test/domain
git commit -m "feat: store TXT chapters and reading progress"
```

---

### Task 8: Reader page, TOC, and progress restore (M3)

**Files:**
- Create: `lib/features/reader/reader_page.dart`
- Create: `lib/features/reader/reader_position.dart`
- Create: `lib/features/reader/toc_drawer.dart`
- Create: `lib/features/reader/reader_settings_sheet.dart`
- Create: `lib/features/reader/reader_providers.dart`
- Modify: `lib/features/library/library_page.dart` (open TXT books)
- Test: `test/features/reader_position_test.dart`
- Test: `test/features/reader_page_test.dart`

**Interfaces:**
- Consumes: `Book`, `Chapter`, `ReadingProgress`, `ChapterRepository`, `ProgressRepository`.
- Produces:
  - `class ResumeLocation { final int chapterIndex; final double fraction; }`
  - `ResumeLocation locateAnchor(List<Chapter> chapters, int charOffset)` — clamps below 0 to the first chapter at 0.0, beyond the end to the last chapter at 1.0, and handles an empty list by returning `(0, 0.0)`.
  - `int offsetForPosition(Chapter chapter, double fraction)` — clamps fraction to 0–1 and returns `chapter.startOffset + (fraction * chapter.contentText.length).round()`, never beyond `chapter.endOffset`.
  - `ReaderPage({required String bookId})` — loads book, chapters, and progress; if no chapters, shows `这本书暂时没有可显示的章节`; on open, updates `lastOpenedAt`.
  - `TocDrawer` — lists chapter titles, highlights the current chapter, tapping jumps to it.
  - Reader view: one chapter per screen in a `SingleChildScrollView`; previous/next chapter buttons; settings sheet with font size 14–28, line height 1.2–2.0, and light/sepia/dark reading background (session-only).
  - Progress: throttled save (500 ms) while scrolling and on chapter change; anchor is the book-global offset computed with `offsetForPosition`. On load, `locateAnchor` picks the chapter and an initial fraction; jump after first layout.
  - Library: tapping a TXT book opens `ReaderPage`; other formats keep the "later milestone" SnackBar.

- [ ] **Step 1: Write the failing position tests**

Create `test/features/reader_position_test.dart`:
```dart
test('locates an offset in the correct chapter', () { ... });
test('clamps offsets before the start and past the end', () { ... });
test('handles empty chapter list', () { ... });
test('offsetForPosition never exceeds chapter end', () {
  final chapter = Chapter(... contentText: '0123456789');
  expect(offsetForPosition(chapter, 1.0), chapter.startOffset + 10);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/reader_position_test.dart`
Expected: FAIL because the position helpers do not exist.

- [ ] **Step 3: Implement the position helpers**

Keep them pure; no Flutter imports.

- [ ] **Step 4: Write the failing reader widget tests**

Create `test/features/reader_page_test.dart` with an in-memory DB seeded with a book, three chapters, and progress pointing into chapter 2. Override providers; pump `ReaderPage`. Assert:
1. chapter 2 content is visible on first frame after settling (restore works);
2. opening the TOC lists all three titles and tapping chapter 3 shows its content;
3. a book with zero chapters shows the empty-chapters message.

- [ ] **Step 5: Run the tests to verify they fail**

Run: `flutter test test/features/reader_page_test.dart`
Expected: FAIL because `ReaderPage` does not exist.

- [ ] **Step 6: Implement the reader UI and progress saving**

Build the chapter view, TOC drawer, and settings sheet. Use a `Timer` for throttled saves; cancel it in `dispose` and save one final position. Use `ScrollController` and post-frame callbacks for restore. Do not persist display settings in this phase.

- [ ] **Step 7: Verify**

Run:
```bash
flutter analyze
flutter test
```
Expected: analyze clean; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib test
git commit -m "feat: add TXT reader with TOC and restored reading position"
```

---

### Task 9: End-to-end verification and documentation (M3)

**Files:**
- Modify: `README.md` (setup, run, test, current limitations)
- Test: none new; use manual verification notes in the README

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: verified Windows + Android runs and documented known limitations.

- [ ] **Step 1: Run the automated checks**

```bash
flutter analyze
flutter test
```
Expected: no analyzer issues; all tests pass.

- [ ] **Step 2: Verify on Windows**

```bash
flutter run -d windows
```
Check by hand:
1. Import a UTF-8 Chinese TXT and a GB18030 Chinese TXT.
2. Both show correct text and a sensible TOC; jumping works.
3. Scroll to the middle of a chapter, close the app, reopen the book; it lands in the same passage.
4. Change font size; the position stays in the same passage.
5. Delete a book; its copied file is gone.

- [ ] **Step 3: Verify on Android**

Start an emulator or connect a device, then:
```bash
flutter run -d <android-device-id>
```
Repeat the import + read + restart checks. At minimum, verify the app installs and a TXT imports and opens.

- [ ] **Step 4: Document**

Update `README.md` with: prerequisites (Flutter, Visual Studio C++ workload, Android SDK), the dependency install command, how to run on Windows/Android, how to run tests, and the phase-1 limitations (EPUB/PDF open only as library entries; no annotations yet; no AI calls; scanned PDFs not supported).

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: document phase 1 setup, verification, and limitations"
```

---

## Out of Scope for This Plan

M4 (EPUB parsing/rendering), M5 (PDF rendering/TOC), M6 (annotations/bookmarks/notes), M7 (AssistantService and AI UI stubs), and M8 (full acceptance) will get their own plans after this phase is verified. Their design decisions are already recorded in the spec.

## Self-Review Notes

- Spec coverage: M0/M1 → Task 1; M2 import/library → Tasks 2–4; M3 TXT reading, encoding, chapters, TOC, progress → Tasks 5–9. Format import for EPUB/PDF is covered at the library level in M2; their readers are explicitly deferred.
- Review Focus tests: encoding → Task 5; false headings and large books → Task 6; filenames/empty files → Task 3; progress restore → Task 8.
- Types and names are consistent across tasks (`BookService`, `Chapter`, `ReadingAnchor`, `decodeTxtBytes`, `detectTxtChapters`, `offsetForPosition`, `locateAnchor`).
