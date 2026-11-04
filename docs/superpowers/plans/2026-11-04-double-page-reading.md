# 双页阅读实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 TXT/EPUB 与漫画 EPUB 增加可选的双页（左右对照）阅读模式，默认双页、持久化；PDF 保持现状。

**Architecture:** 新增纯函数模块 `reader_spread.dart` 承担模式枚举、阈值、页/展开页换算与栏宽计算；`reader_page.dart` 用 `reader.spread` 设置驱动两种渲染路径。文本模式按单栏宽度重新分页，`_pageIndex` 归一到展开页左侧，翻页步长为 2；漫画把 `PageView` 的一页改成一张展开页，进度与书签仍按具体页码存储。

**Tech Stack:** Flutter 3.47 / Dart 3.13, Riverpod 3, Drift, `TextPainter` 分页。

**Spec:** `docs/superpowers/specs/2026-11-04-double-page-reading-design.md`

## Global Constraints

- 设置键 `reader.spread`，取值 `single` / `double`；缺省或非法值一律按 `double`。
- 显示阈值 880 逻辑像素，宽度 `< 880` 按单页渲染，但**不修改**已保存的偏好。
- 双页按章节内配对（方案 A）：每章从展开页左侧开始，不跨章节拼接。
- 页脚全书总数 `Y` 仍是**页数**（`countBookPages` 之和），不换算成展开页数；`X` 是左侧页的全书页码。
- PDF 不改行为：单页滚动、缩放拖动、隐藏滚动条、无双页入口。
- 现有单页测试必须在 800×600 窗口下继续全绿；宽窗口测试显式设置 `tester.view.physicalSize = Size(1400, 900)`、`devicePixelRatio = 1`。
- Flutter 命令：`F:/src/flutter/bin/flutter.bat`；测试加 `--no-pub`；提交前不得推送（用户未授权本轮推送）。
- 每个任务结束提交一次；提交信息沿用仓库的 `feat:` / `fix:` / `docs:` 前缀。

## Review Focus

- 宽窗口打开展开页后把窗口缩到 880 以下：正文必须退回单页且仍停在同一个阅读位置；宽度恢复后回到同一展开页。
- 章节页数为奇数或只有一页：右侧必须是空白栏，且最后一页的“下一页”按展开页判断后正确禁用/跨章。
- 书签或标注落在右侧页（页索引为奇数）：跳转必须打开包含它的展开页，页脚显示 `a–b` 且含该页。
- 漫画在宽窗口固定左栏后正文变窄：阈值按屏幕宽度判断，仍显示两页且不崩；取消固定后状态一致。
- 设置表里没有 `reader.spread` 或存了非法值：必须按双页渲染，而不是单页或崩溃。

---

### Task 1: 展开页几何与页脚区间

**Files:**
- Create: `lib/features/reader/reader_spread.dart`
- Modify: `lib/features/reader/reader_position.dart:60-68`
- Test: `test/features/reader_spread_test.dart`, `test/features/reader_position_test.dart:83-101`

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum ReaderSpread { single, double }`
  - `const double kSpreadMinWidth = 880;`
  - `const double kSpreadContentMaxWidth = 1320;`
  - `const double kSpreadGutterWidth = 24;`
  - `const double kPaneHorizontalPadding = 20;`
  - `ReaderSpread readerSpreadFromName(String? name)`
  - `bool spreadApplies(ReaderSpread spread, double availableWidth)`
  - `int spreadPageIndex(int pageIndex)` — 归一到偶数（展开页左侧）。
  - `int spreadLastPageIndex(int pageIndex, int pageCount)` — 展开页右侧页，缺失时等于左侧页。
  - `int spreadCount(int pageCount)` — `ceil(pageCount / 2)`。
  - `double spreadTextWidth(double availableWidth)` — `(min(width, 1320) - 24) / 2 - 40`。
  - `String readingFooterText({required int pageIndex, int? pageEndIndex, required int? chapterPageCount, int? bookPageIndex, int? bookPageTotal})`

- [ ] **Step 1: 写失败测试**

`test/features/reader_spread_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/reader/reader_spread.dart';

void main() {
  test('defaults to double and rejects unknown values', () {
    expect(readerSpreadFromName(null), ReaderSpread.double);
    expect(readerSpreadFromName('single'), ReaderSpread.single);
    expect(readerSpreadFromName('double'), ReaderSpread.double);
    expect(readerSpreadFromName('triple'), ReaderSpread.double);
  });

  test('applies double only at or above 880 logical pixels', () {
    expect(spreadApplies(ReaderSpread.double, 879.9), isFalse);
    expect(spreadApplies(ReaderSpread.double, 880), isTrue);
    expect(spreadApplies(ReaderSpread.single, 1400), isFalse);
  });

  test('snaps pages to the left of a spread', () {
    expect(spreadPageIndex(0), 0);
    expect(spreadPageIndex(3), 2);
    expect(spreadPageIndex(4), 4);
  });

  test('reports the right page and spread count', () {
    expect(spreadLastPageIndex(2, 5), 3);
    expect(spreadLastPageIndex(4, 5), 4);
    expect(spreadLastPageIndex(0, 1), 0);
    expect(spreadCount(3), 2);
    expect(spreadCount(4), 2);
    expect(spreadCount(0), 0);
  });

  test('computes the pane text width', () {
    expect(spreadTextWidth(1400), 608);
    expect(spreadTextWidth(880), 388);
  });
}
```

在 `test/features/reader_position_test.dart` 的 footer 测试中追加：

```dart
    expect(
      readingFooterText(
        pageIndex: 2,
        pageEndIndex: 3,
        chapterPageCount: 12,
        bookPageIndex: 56,
        bookPageTotal: 320,
      ),
      '第 3–4 / 12 页 · 全书 56 / 320 页',
    );
    expect(
      readingFooterText(
        pageIndex: 0,
        pageEndIndex: 0,
        chapterPageCount: 1,
      ),
      '第 1 / 1 页 · 全书 … / … 页',
    );
```

- [ ] **Step 2: 运行测试确认失败**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/reader_spread_test.dart test/features/reader_position_test.dart`
Expected: FAIL — `reader_spread.dart` 不存在（编译错误），或 `pageEndIndex` 命名参数未定义。

- [ ] **Step 3: 实现**

`lib/features/reader/reader_spread.dart` 按 Interfaces 实现；`readerSpreadFromName` 用 switch 表达式，未知值走 `_ => ReaderSpread.double`；`spreadLastPageIndex` 用 `(spreadPageIndex(pageIndex) + 1).clamp(0, pageCount - 1)`，`pageCount <= 0` 返回 0；`spreadCount` 用 `(pageCount + 1) ~/ 2`。

`readingFooterText` 增加可选 `pageEndIndex`，当 `pageEndIndex != null && pageEndIndex > pageIndex` 时章节部分输出 `第 ${pageIndex + 1}–${pageEndIndex + 1} / ...`，否则保持现有 `第 ${pageIndex + 1} / ...`；全书部分不变。

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2
Expected: PASS（两个文件全部通过）。

- [ ] **Step 5: 提交**

```bash
git add lib/features/reader/reader_spread.dart lib/features/reader/reader_position.dart test/features/reader_spread_test.dart test/features/reader_position_test.dart
git commit -m "feat: add spread geometry helpers and range footers"
```

---

### Task 2: 持久化单页/双页偏好与设置面板

**Files:**
- Modify: `lib/features/reader/reader_settings_sheet.dart`
- Modify: `lib/features/reader/reader_page.dart`（`_ReaderPageState` 设置键与加载/保存、`_openSettings`）
- Test: `test/features/reader_page_test.dart`（设置相关用例，约 536-601 行）

**Interfaces:**
- Consumes: Task 1 的 `ReaderSpread`、`readerSpreadFromName`。
- Produces:
  - `ReaderSettingsSheet({required double fontSize, required double lineHeight, required ReaderBackground background, required ReaderSpread spread, required void Function(double fontSize, double lineHeight, ReaderBackground background, ReaderSpread spread) onChanged})`
  - `_ReaderPageState` 私有字段 `ReaderSpread _spread`（初值 `ReaderSpread.double`）、常量 `_spreadKey = 'reader.spread'`。

- [ ] **Step 1: 写失败测试**

在 `test/features/reader_page_test.dart` 顶部加导入：

```dart
import 'package:hackathon_reading/features/reader/reader_spread.dart';
```

新增三个用例（放在设置用例之后）：

```dart
  testWidgets('defaults to double and persists a switch to single', (
    tester,
  ) async {
    await pumpReader(tester, 'b1');

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final control = tester.widget<SegmentedButton<ReaderSpread>>(
      find.byType(SegmentedButton<ReaderSpread>),
    );
    expect(control.selected, {ReaderSpread.double});

    await tester.tap(find.text('单页'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleAfterIo(tester);

    final stored = await tester.runAsync(
      () => SettingsRepository(db).get('reader.spread'),
    );
    expect(stored, 'single');
    await disposeApp(tester);
  });

  testWidgets('restores the persisted spread into the settings sheet', (
    tester,
  ) async {
    await SettingsRepository(db).set('reader.spread', 'single');
    await pumpReader(tester, 'b1');

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<ReaderSpread>>(
            find.byType(SegmentedButton<ReaderSpread>),
          )
          .selected,
      {ReaderSpread.single},
    );
    await disposeApp(tester);
  });

  testWidgets('treats an unknown spread value as double', (tester) async {
    await SettingsRepository(db).set('reader.spread', 'triple');
    await pumpReader(tester, 'b1');

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<ReaderSpread>>(
            find.byType(SegmentedButton<ReaderSpread>),
          )
          .selected,
      {ReaderSpread.double},
    );
    await disposeApp(tester);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/reader_page_test.dart --plain-name "spread"`
Expected: FAIL — 找不到 `SegmentedButton<ReaderSpread>`。

- [ ] **Step 3: 实现**

`reader_settings_sheet.dart`：导入 `reader_spread.dart`；构造参数增加 `spread`，`onChanged` 改成四参数；在行距滑块与背景之间加：

```dart
          const SizedBox(height: 8),
          const Text('排版'),
          const SizedBox(height: 8),
          SegmentedButton<ReaderSpread>(
            segments: const [
              ButtonSegment(value: ReaderSpread.single, label: Text('单页')),
              ButtonSegment(value: ReaderSpread.double, label: Text('双页')),
            ],
            selected: {spread},
            onSelectionChanged: (selection) =>
                onChanged(fontSize, lineHeight, background, selection.first),
          ),
```

并把现有字号、行距、背景回调改为传 `spread`。

`reader_page.dart`：
- `_ReaderPageState` 增加 `static const _spreadKey = 'reader.spread';` 与 `ReaderSpread _spread = ReaderSpread.double;`
- `_loadReadingSettings` 的 `Future.wait` 增加 `repository.get(_spreadKey)`（index 4）；把 index 4 加入“全空则返回”的判断；`setState` 内 `if (values[4] != null) _spread = readerSpreadFromName(values[4]);`
- `_persistReadingSettings` 增加 `repository.set(_spreadKey, _spread.name).catchError((Object _) {});`
- `_openSettings` 传 `spread: _spread`，回调签名改为四参数并 `_spread = spread;`

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2
Expected: PASS（3 个用例通过）。

- [ ] **Step 5: 提交**

```bash
git add lib/features/reader/reader_settings_sheet.dart lib/features/reader/reader_page.dart test/features/reader_page_test.dart
git commit -m "feat: persist the single/double page spread preference"
```

---

### Task 3: TXT/EPUB 双页排版、翻页与跳转

**Files:**
- Modify: `lib/features/reader/reader_page.dart`（`_goToNextPage`/`_goToPreviousPage`、`LayoutBuilder` 分页与渲染、`_navigationBar`）
- Test: `test/features/reader_page_test.dart`

**Interfaces:**
- Consumes: Task 1 全部纯函数；Task 2 的 `_spread`。
- Produces:
  - `_ReaderPageState` 私有字段 `bool _doubleSpread`，表示当前布局实际采用双页。
  - 空白右栏的稳定 key：`Key('reader-spread-blank')`。

- [ ] **Step 1: 写失败测试**

在测试文件顶层 helper 区域（`tapPrevZone` 之后）加：

```dart
  void useWideWindow(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    tester.binding.handleMetricsChanged();
  }

  String spreadFooterText(WidgetTester tester) =>
      tester.widget<Text>(find.textContaining('全书')).data!;

  String spreadPageText(WidgetTester tester) => tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map(
        (selectable) => selectable.textSpan!.children!
            .cast<TextSpan>()
            .map((span) => span.text ?? '')
            .join(),
      )
      .join();
```

新增用例：

```dart
  testWidgets('defaults to a two-page spread on a wide window', (tester) async {
    await seedLongBook();
    useWideWindow(tester);
    await pumpReader(tester, 'long');

    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(spreadFooterText(tester), startsWith('第 1–2 / '));
    expect(spreadFooterText(tester), contains('全书 '));
    await disposeApp(tester);
  });

  testWidgets('advances two pages at a time in a spread', (tester) async {
    await seedLongBook();
    useWideWindow(tester);
    await pumpReader(tester, 'long');

    await tapNextZone(tester);
    expect(spreadFooterText(tester), startsWith('第 3–4 / '));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(spreadFooterText(tester), startsWith('第 5–6 / '));

    await tester.tap(find.widgetWithText(TextButton, '上一页'));
    await tester.pumpAndSettle();
    expect(spreadFooterText(tester), startsWith('第 3–4 / '));
    await disposeApp(tester);
  });

  testWidgets('narrow windows fall back to a single page', (tester) async {
    await seedLongBook();
    useWideWindow(tester);
    await pumpReader(tester, 'long');
    expect(find.byType(SelectableText), findsNWidgets(2));

    tester.view.physicalSize = const Size(800, 600);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      spreadFooterText(tester),
      matches(RegExp(r'^第 \d+ / \d+ 页 · ')),
    );

    tester.view.physicalSize = const Size(1400, 900);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(2));
    await disposeApp(tester);
  });

  testWidgets('a one-page chapter leaves the right pane blank', (tester) async {
    await seedHeadingBook(
      id: 'spread-empty',
      titles: ['空章', '有字'],
      levels: [1, 1],
      texts: ['', '有字的内容。'],
    );
    useWideWindow(tester);
    await pumpReader(tester, 'spread-empty');

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byKey(const Key('reader-spread-blank')), findsOneWidget);
    expect(spreadFooterText(tester), startsWith('第 1 / 1 页'));

    await tapNextZone(tester);
    expect(find.textContaining('有字的内容。'), findsOneWidget);
    await tapNextZone(tester);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '下一页')).onPressed,
      isNull,
    );
    await disposeApp(tester);
  });

  testWidgets('chapters restart on the left of a fresh spread', (tester) async {
    await seedTwoChapterBook();
    useWideWindow(tester);
    await pumpReader(tester, 'jb');

    var guard = 0;
    while (find.textContaining('跳转测试 · 第二章').evaluate().isEmpty &&
        guard++ < 200) {
      await tapNextZone(tester);
    }
    expect(find.textContaining('跳转测试 · 第二章'), findsOneWidget);
    expect(spreadFooterText(tester), startsWith('第 1–2 / '));

    await tapPrevZone(tester);
    expect(find.textContaining('跳转测试 · 第一章'), findsOneWidget);
    final match = RegExp(
      r'^第 (\d+)–(\d+) / (\d+) 页',
    ).firstMatch(spreadFooterText(tester))!;
    expect(match.group(2), match.group(3));
    await disposeApp(tester);
  });

  testWidgets('a saved position opens the spread containing it', (tester) async {
    await seedMarkerProgress();
    useWideWindow(tester);
    await pumpReader(tester, 'long');

    expect(find.textContaining('第40段'), findsOneWidget);
    expect(spreadFooterText(tester), isNot(startsWith('第 1–')));
    await disposeApp(tester);
  });

  testWidgets('a bookmark jump opens the spread containing the anchor', (
    tester,
  ) async {
    await seedTwoChapterBook();
    final text0 = (await ChapterRepository(db).getContent('jb', 0))!;
    final text1 = (await ChapterRepository(db).getContent('jb', 1))!;
    final marker = text0.length + text1.indexOf('乙第30段');
    await seedBookmark(
      id: 'bm-spread',
      bookId: 'jb',
      chapterId: 'jb-c1',
      anchorStart: marker,
    );
    useWideWindow(tester);
    await pumpReader(tester, 'jb');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();

    expect(find.textContaining('乙第30段'), findsOneWidget);
    expect(spreadFooterText(tester), contains('–'));
    await disposeApp(tester);
  });

  testWidgets('a font change keeps the spread anchor', (tester) async {
    await seedMarkerProgress();
    useWideWindow(tester);
    await pumpReader(tester, 'long');
    final anchorText = spreadPageText(tester).substring(0, 10);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(150, 0));
    await tester.pumpAndSettle();

    expect(spreadPageText(tester), contains(anchorText));
    expect(spreadFooterText(tester), contains('–'));
    await disposeApp(tester);
  });
```

同时修改现有 `caps the reading column at 720 logical pixels`：在 `pumpReader` 之前写入 `await SettingsRepository(db).set('reader.spread', 'single');`，否则宽窗口会渲染两栏导致 `tester.getSize(find.byType(SelectableText))` 命中多个组件。

- [ ] **Step 2: 运行测试确认失败**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/reader_page_test.dart`
Expected: FAIL — 宽窗口仍只有一个 `SelectableText`，页脚为单页格式；空白栏 key 不存在。

- [ ] **Step 3: 实现**

1. 状态：增加 `bool _doubleSpread = false;`。
2. `_goToNextPage` / `_goToPreviousPage`：

```dart
final step = _doubleSpread ? 2 : 1;
if (_pageIndex + step < pagination.pageCount) { ... _pageIndex += step ... }
```

上一页同理用 `_pageIndex - step >= 0`。

3. `LayoutBuilder` 内：

```dart
final doubleSpread = spreadApplies(_spread, constraints.maxWidth);
final textWidth = doubleSpread
    ? spreadTextWidth(constraints.maxWidth).clamp(1.0, double.infinity)
    : (constraints.maxWidth.clamp(0.0, 720.0) - 40).clamp(1.0, 720.0);
```

分页 key 与 `bookSignature` 都追加 `|${doubleSpread ? 'double' : 'single'}`。

页码归一：

```dart
var pageIndex = pending != null
    ? pagination.pageIndexForOffset(pending - currentChapter.startOffset)
    : _pageIndex;
pageIndex = pageIndex.clamp(0, pagination.pageCount - 1);
if (doubleSpread) pageIndex = spreadPageIndex(pageIndex);
final spreadChanged = _doubleSpread != doubleSpread;
_doubleSpread = doubleSpread;
```

保留 `_pageIndex = pageIndex; _pendingOffset = null;`；把原来的 `if (pending != null)` 帧后 `setState` 改为 `if (pending != null || spreadChanged)`。

4. 渲染：保留左右 30% 点击区。正文改为：

- 单页路径保持现有 `Padding(20,16,20,32)` + 单栏。
- 双页路径：

```dart
Center(
  child: SizedBox(
    width: constraints.maxWidth.clamp(0.0, kSpreadContentMaxWidth),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kPaneHorizontalPadding,
              ),
              child: pane(pageIndex),
            ),
          ),
          VerticalDivider(
            width: kSpreadGutterWidth,
            thickness: 1,
            color: _colors.$2.withValues(alpha: 0.12),
          ),
          Expanded(
            child: pageIndex + 1 < pagination.pageCount
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kPaneHorizontalPadding,
                    ),
                    child: pane(pageIndex + 1),
                  )
                : const SizedBox.expand(key: Key('reader-spread-blank')),
          ),
        ],
      ),
    ),
  ),
)
```

`pane(int index)` 是 builder 内的局部函数：取出 `pagination.pageAt(index)`，生成 spans 与 `pageContent`，返回现有 `ClipRect > Align > KeyedSubtree(key: ValueKey('${chapter.id}-$index-$_paginationKey')) > SelectableText.rich` 结构（保持 `NeverScrollableScrollPhysics` 与 `_selectionToolbar`）。

5. `_navigationBar`：

```dart
final pageNumber = (_doubleSpread ? spreadPageIndex(_pageIndex) : _pageIndex)
    .clamp(0, pageCount - 1);
final pageEndIndex = _doubleSpread
    ? spreadLastPageIndex(pageNumber, pageCount)
    : null;
final step = _doubleSpread ? 2 : 1;
final atBookEnd =
    index == chapters.length - 1 && _pageIndex + step >= pageCount;
```

`readingFooterText` 调用增加 `pageEndIndex: pageEndIndex`。

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2
Expected: PASS（含原有单页用例）。

- [ ] **Step 5: 提交**

```bash
git add lib/features/reader/reader_page.dart test/features/reader_page_test.dart
git commit -m "feat: render TXT and EPUB chapters as two-page spreads"
```

---

### Task 4: 漫画双页与顶部切换

**Files:**
- Modify: `lib/features/reader/reader_top_bar.dart`
- Modify: `lib/features/reader/reader_page.dart`（`_buildComic`、`_comicPage`、`_onComicPageChanged`、`_goToComicPage`、`_persistComicProgress`、`_comicNavigationBar`、快捷键）
- Test: `test/features/reader_page_test.dart`（`comic reader` group）

**Interfaces:**
- Consumes: Task 1 的 `spreadApplies`、`spreadPageIndex`、`spreadCount`；Task 2 的 `_spread`。
- Produces:
  - `ReaderTopBar` 新增可选参数 `VoidCallback? onToggleSpread` 与 `bool doubleSpread = false`；按钮 key 为 `Key('reader-spread-toggle')`，tooltip 为当前模式（`双页` / `单页`）。
  - `_ReaderPageState` 私有字段 `bool _comicDouble = false;` 与方法 `_shiftComicSpread(int delta)`、`_toggleSpread()`。

- [ ] **Step 1: 写失败测试**

在 `comic reader` group 的 helper 区域加（`pumpComic` 之后）：

```dart
    Future<void> pumpComicWide(WidgetTester tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      tester.binding.handleMetricsChanged();
      await pumpComic(tester);
    }
```

新增用例：

```dart
    testWidgets('renders two comic pages per spread on a wide window', (
      tester,
    ) async {
      await pumpComicWide(tester);

      expect(find.byKey(const Key('comic-page-0')), findsOneWidget);
      expect(find.byKey(const Key('comic-page-1')), findsOneWidget);
      expect(find.text('测试漫画 · 第 1 / 3 页'), findsOneWidget);
      expect(find.text('第 1 / 3 页 · 33%'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('moves comic spreads with buttons and keys', (tester) async {
      await pumpComicWide(tester);

      await tester.tap(find.widgetWithText(TextButton, '下一页'));
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 3 / 3 页'), findsOneWidget);
      expect(find.text('第 3 / 3 页 · 100%'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '上一页'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 3 / 3 页'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 1 / 3 页'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('the top bar toggles the spread and persists it', (
      tester,
    ) async {
      await pumpComicWide(tester);
      expect(find.byTooltip('双页'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader-spread-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comic-page-1')), findsNothing);
      expect(find.byTooltip('单页'), findsOneWidget);

      final stored = await tester.runAsync(
        () => SettingsRepository(db).get('reader.spread'),
      );
      expect(stored, 'single');

      await tester.tap(find.byKey(const Key('reader-spread-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comic-page-1')), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('a saved comic page opens its spread', (tester) async {
      await ProgressRepository(db).save(
        ReadingProgress(
          bookId: 'manga',
          anchor: const ReadingAnchor.page(2),
          percent: 2 / 3,
          updatedAt: DateTime(2026, 1, 6),
        ),
      );
      await pumpComicWide(tester);

      expect(find.text('测试漫画 · 第 1 / 3 页'), findsOneWidget);
      expect(find.byKey(const Key('comic-page-1')), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('the drawer jump opens the spread containing the page', (
      tester,
    ) async {
      await pumpComicWide(tester);

      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一话'));
      await tester.pumpAndSettle();

      expect(find.text('测试漫画 · 第 1 / 3 页'), findsOneWidget);
      expect(find.byKey(const Key('comic-page-1')), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('pinning the rail keeps a coherent spread', (tester) async {
      await pumpComicWide(tester);

      await tester.tap(find.byTooltip('固定左栏'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader-rail-pinned')), findsOneWidget);
      expect(find.byKey(const Key('comic-page-0')), findsOneWidget);
      expect(find.byKey(const Key('comic-page-1')), findsOneWidget);
      await disposeApp(tester);
    });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `F:/src/flutter/bin/flutter.bat test --no-pub test/features/reader_page_test.dart --plain-name "comic"`
Expected: FAIL — 宽窗口仍按单页显示，`comic-page-1` 不存在，顶部无 `reader-spread-toggle`。

- [ ] **Step 3: 实现**

`reader_top_bar.dart`：增加 `onToggleSpread`、`doubleSpread`；在标题与目录按钮之间插入：

```dart
if (onToggleSpread != null)
  IconButton(
    key: const Key('reader-spread-toggle'),
    tooltip: doubleSpread ? '双页' : '单页',
    icon: Icon(
      doubleSpread ? Icons.auto_stories_outlined : Icons.crop_portrait,
    ),
    onPressed: onToggleSpread,
  ),
```

`reader_page.dart` 漫画：

1. `_buildComic` 的 data 分支开头：

```dart
final doubleSpread =
    spreadApplies(_spread, MediaQuery.sizeOf(context).width);
```

初始化：

```dart
if (!_comicInitialized) {
  _comicInitialized = true;
  _comicPageCount = total;
  final saved = data.progress?.anchor.page ?? 1;
  _comicPageIndex = (saved - 1).clamp(0, total - 1);
  _comicDouble = doubleSpread;
  _comicController = PageController(
    initialPage: doubleSpread ? _comicPageIndex ~/ 2 : _comicPageIndex,
  );
} else if (_comicPageCount != total) {
  _comicPageCount = total;
  _comicPageIndex = _comicPageIndex.clamp(0, total - 1);
}
if (_comicDouble != doubleSpread) {
  _comicDouble = doubleSpread;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final controller = _comicController;
    if (controller == null || !controller.hasClients) return;
    controller.jumpToPage(
      _comicDouble ? _comicPageIndex ~/ 2 : _comicPageIndex,
    );
  });
}
final leftPage = _comicDouble
    ? spreadPageIndex(_comicPageIndex)
    : _comicPageIndex.clamp(0, total - 1);
final percent = (leftPage + 1) / total;
```

标题、页脚、书签状态、`_toggleComicBookmark` 都用 `leftPage + 1`；`ComicTocDrawer` 的 `currentIndex` 传 `leftPage`。

2. `PageView`：

```dart
itemCount: _comicDouble ? spreadCount(total) : total,
itemBuilder: (context, itemIndex) {
  if (!_comicDouble) return _comicPage(pages[itemIndex], itemIndex);
  final left = itemIndex * 2;
  final right = left + 1;
  return Row(
    children: [
      Expanded(child: _comicPage(pages[left], left)),
      SizedBox(width: kSpreadGutterWidth, child: ColoredBox(color: _colors.$1)),
      Expanded(
        child: right < total
            ? _comicPage(pages[right], right)
            : const SizedBox.shrink(),
      ),
    ],
  );
},
```

3. `_onComicPageChanged(int itemIndex)`：

```dart
final concrete = _comicDouble
    ? (itemIndex * 2).clamp(0, _comicPageCount - 1)
    : itemIndex.clamp(0, _comicPageCount - 1);
```

4. `_goToComicPage(int page)`：目标具体页 `target`；控制器目标 `item = _comicDouble ? target ~/ 2 : target`；无控制器时 `_comicPageIndex = _comicDouble ? spreadPageIndex(target) : target`。

5. 新增：

```dart
void _shiftComicSpread(int delta) {
  if (_comicPageCount <= 0) return;
  final step = _comicDouble ? 2 : 1;
  final target = _comicPageIndex + delta * step;
  if (target < 0 || target >= _comicPageCount) return;
  _goToComicPage(target);
}

void _toggleSpread() {
  final next = _spread == ReaderSpread.double
      ? ReaderSpread.single
      : ReaderSpread.double;
  final chapters = _cachedData?.chapters ?? const <Chapter>[];
  final comic = _cachedData?.book?.comic ?? false;
  final anchor = comic ? null : _currentPageStartOffset(chapters);
  setState(() {
    if (anchor != null) _pendingOffset = anchor;
    _spread = next;
  });
  _settingsRepository?.set(_spreadKey, next.name).catchError((Object _) {});
}
```

6. 快捷键：箭头键与 PageUp/PageDown 都改为 `_shiftComicSpread(±1)`；`_comicNavigationBar` 的按钮同样调用 `_shiftComicSpread`，禁用条件用 `index - step >= 0` / `index + step < total`（`step = _comicDouble ? 2 : 1`）。

7. 顶部栏传入 `doubleSpread: _comicDouble`、`onToggleSpread: _toggleSpread`。

8. `_persistComicProgress`：

```dart
final left = _comicDouble ? spreadPageIndex(_comicPageIndex) : _comicPageIndex;
final page = left.clamp(0, total - 1) + 1;
```

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2
Expected: PASS（原有单页漫画用例 + 新增双页用例）。

- [ ] **Step 5: 提交**

```bash
git add lib/features/reader/reader_top_bar.dart lib/features/reader/reader_page.dart test/features/reader_page_test.dart
git commit -m "feat: add two-page spreads to the comic reader"
```

---

### Task 5: 文档与全量验证

**Files:**
- Modify: `README.md`（验收清单、测试数）
- Modify: `CONTRIBUTING.md`（测试数）
- Modify: `docs/superpowers/specs/2026-11-04-double-page-reading-design.md`（如实现期间有偏差）
- Memory: `C:\Users\icetea\.claude\projects\F--hackathon-reading\memory\tasks\2026-11-04-double-page-reading.md` 与 `memory/tasks/INDEX.md`

**Interfaces:**
- Consumes: 前四个任务。
- Produces: 与代码一致的验收说明。

- [ ] **Step 1: 更新文档**

- README 验收清单追加一项：`- 双页阅读：阅读设置切换单页/双页（默认双页），TXT/EPUB 与漫画左右对照、按展开页翻页，窄窗口自动单页；PDF 仍为单页滚动。`
- 跑完全量测试后，把 README/CONTRIBUTING 中的测试数改为新的实测值（当前基线 411）。
- 若实现与设计文档有差异（例如漫画阈值用屏幕宽度），同步到设计文档。

- [ ] **Step 2: 全量验证**

Run: `F:/src/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

Run: `F:/src/flutter/bin/flutter.bat test --no-pub`
Expected: 全部通过，无残留 `flutter_tester`；记录实际测试数并回填文档。

- [ ] **Step 3: 提交**

```bash
git add README.md CONTRIBUTING.md docs/superpowers/specs/2026-11-04-double-page-reading-design.md
git commit -m "docs: document the double-page reading mode"
```

- [ ] **Step 4: 写任务记录**

在 `memory/tasks/2026-11-04-double-page-reading.md` 记录：需求、四个提交、关键决策（默认双页、880 阈值、章节内配对、漫画按屏幕宽度判断、PDF 不变）、测试数与未做的 GUI 验收项；在 `memory/tasks/INDEX.md` 增加一行索引。

---

## 验收对照

- 默认双页、设置可切单页并持久化 → Task 2。
- 宽窗口左右两栏、一次两页、页脚区间 → Task 3。
- 章节从左侧开始、奇数页右栏空白、不跨章 → Task 3。
- 进度/书签/标注/目录落点 → Task 3。
- 漫画双页、顶部切换、进度按左侧页 → Task 4。
- 窄窗口回退、正文不可滚动 → Task 3（滚动条回归用例已在基线）。
- PDF 不变 → 不改 `pdf_reader_page.dart`，基线用例覆盖。
