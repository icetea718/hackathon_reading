import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/annotation_repository.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/data/repositories/progress_repository.dart';
import 'package:hackathon_reading/data/repositories/settings_repository.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/domain/models/annotation.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/domain/models/reading_progress.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';
import 'package:hackathon_reading/features/companion/companion_avatar.dart';
import 'package:hackathon_reading/features/companion/companion_clip.dart';
import 'package:hackathon_reading/features/companion/companion_quotes.dart';
import 'package:hackathon_reading/features/illustration/illustration_composer_page.dart';
import 'package:hackathon_reading/features/illustration/illustration_jobs.dart';
import 'package:hackathon_reading/illustration/illustration_config.dart';
import 'package:hackathon_reading/illustration/illustration_models.dart';
import 'package:hackathon_reading/illustration/illustration_service.dart';
import 'package:hackathon_reading/features/reader/annotation_spans.dart';
import 'package:hackathon_reading/features/reader/reader_page.dart';
import 'package:hackathon_reading/features/reader/reader_settings_sheet.dart';
import 'package:hackathon_reading/features/reader/reader_spread.dart';

const _jobEffective = IllustrationEffective(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'key',
  chatModel: 'chat',
  imageModel: 'image',
);

const _jobConfig = IllustrationConfig(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'key',
  chatModel: 'chat',
  imageModel: 'image',
);

const _jobLlm = LlmConfig(
  baseUrl: 'https://api.example.com/v1',
  model: 'chat',
  apiKey: 'key',
);

IllustrationResult _jobResult() => IllustrationResult(
      plan: const IllustrationPlan(
        medium: '水彩',
        sketchPrompt: 'sketch',
        colorPrompt: 'color',
      ),
      sketchFile: File('sketch.png'),
      finalFile: File('final.png'),
    );

class _ReaderFakeService extends IllustrationService {
  _ReaderFakeService(this._run) : super(effective: _jobEffective);

  final Future<IllustrationResult> Function(
    void Function(IllustrationStage stage)? onStage,
  ) _run;

  @override
  Future<IllustrationResult> generate(
    String text, {
    void Function(IllustrationStage stage)? onStage,
  }) {
    return _run(onStage);
  }

  @override
  void dispose() {}
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final books = BookRepository(db);
    await books.upsert(
      Book(
        id: 'b1',
        title: '测试小说',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/b1.txt',
        addedAt: DateTime(2026, 1, 1),
      ),
    );
    await books.upsert(
      Book(
        id: 'b2',
        title: '空书',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/b2.txt',
        addedAt: DateTime(2026, 1, 2),
      ),
    );

    const texts = ['第一章的内容', '第二章的内容', '第三章的内容'];
    var offset = 0;
    final chapters = <Chapter>[];
    for (var i = 0; i < texts.length; i++) {
      chapters.add(
        Chapter(
          id: 'c$i',
          bookId: 'b1',
          index: i,
          title: '第${i + 1}章',
          startOffset: offset,
          endOffset: offset + texts[i].length,
          contentText: texts[i],
        ),
      );
      offset += texts[i].length;
    }
    await ChapterRepository(db).replaceForBook('b1', chapters);
    await ProgressRepository(db).save(
      ReadingProgress(
        bookId: 'b1',
        anchor: const ReadingAnchor(charOffset: 8),
        percent: 8 / 18,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpReader(
    WidgetTester tester,
    String bookId, {
    TargetPlatform? platform,
    BookStorage? storage,
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          if (storage != null)
            bookStorageProvider.overrideWith((ref) async => storage),
          ...overrides,
        ],
        child: MaterialApp(
          theme: platform == null ? null : ThemeData(platform: platform),
          home: ReaderPage(bookId: bookId),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> seedLongBook({int lines = 60}) async {
    final buffer = StringBuffer();
    for (var i = 0; i < lines; i++) {
      buffer.writeln('第$i段：这是一段用来撑长页面的正文内容，确保可以滚动。');
    }
    final text = buffer.toString();
    final books = BookRepository(db);
    await books.upsert(
      Book(
        id: 'long',
        title: '长书',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/long.txt',
        addedAt: DateTime(2026, 1, 3),
      ),
    );
    await ChapterRepository(db).replaceForBook('long', [
      Chapter(
        id: 'long-c0',
        bookId: 'long',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: text.length,
        contentText: text,
      ),
    ]);
  }

  Future<void> seedHeadingBook({
    required String id,
    required List<String> titles,
    required List<int> levels,
    required List<String> texts,
  }) async {
    await BookRepository(db).upsert(
      Book(
        id: id,
        title: '层级书',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/$id.txt',
        addedAt: DateTime(2026, 1, 5),
      ),
    );
    var offset = 0;
    final chapters = <Chapter>[];
    for (var i = 0; i < texts.length; i++) {
      chapters.add(
        Chapter(
          id: '$id-c$i',
          bookId: id,
          index: i,
          title: titles[i],
          startOffset: offset,
          endOffset: offset + texts[i].length,
          contentText: texts[i],
          level: levels[i],
        ),
      );
      offset += texts[i].length;
    }
    await ChapterRepository(db).replaceForBook(id, chapters);
  }

  Future<void> seedBookmark({
    String id = 'bm1',
    String bookId = 'b1',
    required String chapterId,
    required int anchorStart,
    AnnotationType type = AnnotationType.bookmark,
  }) async {
    await AnnotationRepository(db).upsert(
      Annotation(
        id: id,
        bookId: bookId,
        chapterId: chapterId,
        type: type,
        anchorStart: anchorStart,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  Future<void> seedHighlight({
    String id = 'hl1',
    String bookId = 'b1',
    required String chapterId,
    required int anchorStart,
    required int anchorEnd,
    AnnotationType type = AnnotationType.highlight,
    String? color = 'green',
    String selectedText = '',
    String noteText = '',
  }) async {
    await AnnotationRepository(db).upsert(
      Annotation(
        id: id,
        bookId: bookId,
        chapterId: chapterId,
        type: type,
        anchorStart: anchorStart,
        anchorEnd: anchorEnd,
        selectedText: selectedText,
        color: color,
        noteText: noteText,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  List<TextSpan> renderedSpans(WidgetTester tester) {
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    return selectable.textSpan!.children!.cast<TextSpan>().toList();
  }

  TextSpan spanWithText(WidgetTester tester, String text) {
    return renderedSpans(tester).firstWhere((span) => span.text == text);
  }

  Future<void> settleAfterIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<Annotation>?> storedBookmarks(
    WidgetTester tester, {
    String bookId = 'b1',
  }) {
    return tester.runAsync(
      () => AnnotationRepository(
        db,
      ).getForBook(bookId, type: AnnotationType.bookmark),
    );
  }

  Future<int> seedTwoChapterBook() async {
    String chapterText(String name) {
      final buffer = StringBuffer();
      for (var i = 0; i < 60; i++) {
        buffer.writeln('$name第$i段：这是一段用来撑长页面的正文内容，确保可以滚动。');
      }
      return buffer.toString();
    }

    final text0 = chapterText('甲');
    final text1 = chapterText('乙');
    await BookRepository(db).upsert(
      Book(
        id: 'jb',
        title: '跳转测试',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/jb.txt',
        addedAt: DateTime(2026, 1, 4),
      ),
    );
    await ChapterRepository(db).replaceForBook('jb', [
      Chapter(
        id: 'jb-c0',
        bookId: 'jb',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: text0.length,
        contentText: text0,
      ),
      Chapter(
        id: 'jb-c1',
        bookId: 'jb',
        index: 1,
        title: '第二章',
        startOffset: text0.length,
        endOffset: text0.length + text1.length,
        contentText: text1,
      ),
    ]);
    return text0.length + text1.length ~/ 2;
  }

  String pageText(WidgetTester tester) =>
      renderedSpans(tester).map((span) => span.text ?? '').join();

  String footerText(WidgetTester tester) =>
      tester.widget<Text>(find.textContaining(RegExp(r'^第 \d+ / '))).data!;

  Future<void> settleBookCount(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await settleAfterIo(tester);
      if (!footerText(tester).contains('…')) return;
    }
  }

  Future<void> tapNextZone(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('reader-next-zone')));
    await tester.pumpAndSettle();
  }

  Future<void> tapPrevZone(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('reader-prev-zone')));
    await tester.pumpAndSettle();
  }

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

  String firstPaneText(WidgetTester tester) => tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .first
      .textSpan!
      .children!
      .cast<TextSpan>()
      .map((span) => span.text ?? '')
      .join();

  double paneTextBottom(WidgetTester tester, SelectableText pane) {
    final state = tester.state<EditableTextState>(
      find.descendant(
        of: find.byWidget(pane),
        matching: find.byType(EditableText),
      ),
    );
    final text = pane.textSpan!.children!
        .cast<TextSpan>()
        .map((span) => span.text ?? '')
        .join()
        .trimRight();
    final boxes = state.renderEditable.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    return boxes.fold<double>(
      0,
      (value, box) => box.bottom > value ? box.bottom : value,
    );
  }

  double paneClipHeight(WidgetTester tester, SelectableText pane) =>
      tester
          .renderObject<RenderBox>(
            find
                .ancestor(
                  of: find.byWidget(pane),
                  matching: find.byType(ClipRect),
                )
                .first,
          )
          .size
          .height;

  testWidgets('flips pages with tap zones, keys, and footer buttons', (
    tester,
  ) async {
    await seedLongBook();
    await pumpReader(tester, 'long');

    expect(footerText(tester), startsWith('第 1 / '));
    final firstPage = pageText(tester);

    await tapNextZone(tester);
    expect(footerText(tester), matches(RegExp(r'^第 2 / \d+ 页 · ')));
    expect(pageText(tester), isNot(firstPage));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(footerText(tester), matches(RegExp(r'^第 3 / \d+ 页 · ')));
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(footerText(tester), matches(RegExp(r'^第 2 / \d+ 页 · ')));

    await tester.tap(find.widgetWithText(TextButton, '下一页'));
    await tester.pumpAndSettle();
    expect(footerText(tester), matches(RegExp(r'^第 3 / \d+ 页 · ')));
    await tester.tap(find.widgetWithText(TextButton, '上一页'));
    await tester.pumpAndSettle();
    expect(footerText(tester), matches(RegExp(r'^第 2 / \d+ 页 · ')));

    await disposeApp(tester);
  });

  testWidgets('turns a page without a transition animation', (tester) async {
    await seedLongBook();
    await pumpReader(tester, 'long');

    await tester.tap(find.byKey(const Key('reader-next-zone')));
    await tester.pump();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(footerText(tester), matches(RegExp(r'^第 2 / \d+ 页 · ')));
    await disposeApp(tester);
  });

  testWidgets('locks the reading surface and hides desktop scrollbars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await seedLongBook(lines: 200);
    await pumpReader(tester, 'long', platform: TargetPlatform.windows);

    expect(find.byType(Scrollbar), findsNothing);
    final body = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(body.scrollPhysics, isA<NeverScrollableScrollPhysics>());

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    expect(find.text('第一章'), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('keyboard paging during a chapter load does not skip chapters', (
    tester,
  ) async {
    String longText(String name) {
      final buffer = StringBuffer();
      for (var i = 0; i < 60; i++) {
        buffer.writeln('$name第$i段：这是一段用来撑长页面的正文内容。');
      }
      return buffer.toString();
    }

    await seedHeadingBook(
      id: 'busy',
      titles: ['第一章', '第二章', '第三章'],
      levels: [1, 1, 1],
      texts: [longText('甲'), longText('乙'), longText('丙')],
    );
    await pumpReader(tester, 'busy');

    while (true) {
      final match = RegExp(
        r'^第 (\d+) / (\d+) 页',
      ).firstMatch(footerText(tester))!;
      if (match.group(1) == match.group(2)) break;
      await tapNextZone(tester);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.textContaining('层级书 · 第二章'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('ignores taps in the middle and the rail hotzone', (
    tester,
  ) async {
    await seedLongBook();
    await pumpReader(tester, 'long');
    final before = footerText(tester);
    final rect = tester.getRect(find.byKey(const Key('reader-page')));

    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(footerText(tester), before);

    await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
    await tester.pumpAndSettle();
    expect(footerText(tester), before);

    await disposeApp(tester);
  });

  testWidgets('starts on the page containing saved progress', (tester) async {
    await seedLongBook();
    final text = (await ChapterRepository(db).getContent('long', 0))!;
    final marker = text.indexOf('第40段');
    await ProgressRepository(db).save(
      ReadingProgress(
        bookId: 'long',
        anchor: ReadingAnchor(charOffset: marker),
        percent: marker / text.length,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await pumpReader(tester, 'long');

    expect(find.textContaining('第40段'), findsOneWidget);
    expect(footerText(tester), isNot(startsWith('第 1 /')));

    await disposeApp(tester);
  });

  testWidgets('crosses into the next chapter and back at the boundaries', (
    tester,
  ) async {
    await seedTwoChapterBook();
    await pumpReader(tester, 'jb');

    final firstChapterPages = int.parse(
      RegExp(r'^第 \d+ / (\d+) 页').firstMatch(footerText(tester))!.group(1)!,
    );
    for (var i = 1; i < firstChapterPages; i++) {
      await tapNextZone(tester);
    }
    expect(
      footerText(tester),
      startsWith('第 $firstChapterPages / $firstChapterPages 页'),
    );
    expect(find.textContaining('跳转测试 · 第一章'), findsOneWidget);

    await tapNextZone(tester);
    expect(find.textContaining('跳转测试 · 第二章'), findsOneWidget);
    expect(footerText(tester), matches(RegExp(r'^第 1 / \d+ 页 · ')));

    await tapPrevZone(tester);
    expect(find.textContaining('跳转测试 · 第一章'), findsOneWidget);
    expect(
      footerText(tester),
      startsWith('第 $firstChapterPages / $firstChapterPages 页'),
    );

    await disposeApp(tester);
  });

  testWidgets('renders a stored highlight on a later page', (tester) async {
    await seedLongBook();
    final text = (await ChapterRepository(db).getContent('long', 0))!;
    final marker = text.indexOf('第40段');
    await ProgressRepository(db).save(
      ReadingProgress(
        bookId: 'long',
        anchor: ReadingAnchor(charOffset: marker),
        percent: marker / text.length,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await seedHighlight(
      bookId: 'long',
      chapterId: 'long-c0',
      anchorStart: marker,
      anchorEnd: marker + 4,
      color: 'green',
    );
    await pumpReader(tester, 'long');

    expect(footerText(tester), isNot(startsWith('第 1 /')));
    final highlighted = renderedSpans(tester)
        .where((span) => span.style?.backgroundColor == highlightColorFor('green'))
        .toList();
    expect(highlighted, isNotEmpty);
    expect(highlighted.first.text, '第40段');
    expect(pageText(tester), contains(highlighted.first.text!));

    await disposeApp(tester);
  });

  testWidgets('navigates an empty chapter and disables the book edges', (
    tester,
  ) async {
    await seedHeadingBook(
      id: 'empty',
      titles: ['空章', '有字'],
      levels: [1, 1],
      texts: ['', '有字的内容。'],
    );
    await pumpReader(tester, 'empty');

    expect(find.textContaining('层级书 · 空章'), findsOneWidget);
    expect(footerText(tester), matches(RegExp(r'^第 1 / 1 页 · ')));
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '上一页')).onPressed,
      isNull,
    );

    await tapNextZone(tester);
    expect(find.textContaining('有字的内容。'), findsOneWidget);
    expect(footerText(tester), matches(RegExp(r'^第 1 / 1 页 · ')));

    await tapNextZone(tester);
    expect(footerText(tester), matches(RegExp(r'^第 1 / 1 页 · ')));
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '下一页')).onPressed,
      isNull,
    );

    await tapPrevZone(tester);
    expect(find.textContaining('层级书 · 空章'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('restores persisted reading settings', (tester) async {
    final settings = SettingsRepository(db);
    await settings.set('reader.fontSize', '24');
    await settings.set('reader.lineHeight', '1.8');
    await settings.set('reader.background', 'dark');
    await pumpReader(tester, 'b1');

    final first = renderedSpans(tester).first;

    expect(first.style?.fontSize, 24);
    expect(first.style?.height, 1.8);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider).first).value, 24);
    expect(tester.widget<Slider>(find.byType(Slider).last).value, 1.8);
    expect(
      tester
          .widget<SegmentedButton<ReaderBackground>>(
            find.byType(SegmentedButton<ReaderBackground>),
          )
          .selected,
      {ReaderBackground.dark},
    );
    await disposeApp(tester);
  });

  testWidgets('persists reading settings changes', (tester) async {
    await pumpReader(tester, 'b1');

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleAfterIo(tester);

    final settings = SettingsRepository(db);
    final fontSize = await tester.runAsync(
      () => settings.get('reader.fontSize'),
    );
    final background = await tester.runAsync(
      () => settings.get('reader.background'),
    );

    expect(double.parse(fontSize!), greaterThan(18));
    expect(background, 'dark');
    await disposeApp(tester);
  });

  testWidgets('ignores invalid settings and clamps out-of-range values', (
    tester,
  ) async {
    final settings = SettingsRepository(db);
    await settings.set('reader.fontSize', 'not-a-number');
    await settings.set('reader.lineHeight', '99');
    await settings.set('reader.background', 'purple');
    await pumpReader(tester, 'b1');

    final first = renderedSpans(tester).first;

    expect(first.style?.fontSize, 18);
    expect(first.style?.height, 2.0);
    await disposeApp(tester);
  });

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

    await tester.ensureVisible(find.text('单页'));
    await tester.pumpAndSettle();
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

  testWidgets('restores the chapter from saved progress', (tester) async {
    await pumpReader(tester, 'b1');
    expect(find.textContaining('第二章的内容'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('TOC lists chapters and jumps to a selected one', (tester) async {
    await pumpReader(tester, 'b1');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('第1章'), findsOneWidget);
    expect(find.text('第2章'), findsOneWidget);
    expect(find.text('第3章'), findsOneWidget);

    await tester.tap(find.text('第3章'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第三章的内容'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('TOC indents nested sections under their part', (tester) async {
    await BookRepository(db).upsert(
      Book(
        id: 'nested',
        title: '层级书',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/nested.txt',
        addedAt: DateTime(2026, 1, 4),
      ),
    );
    const texts = ['第一部分的内容', '择善的内容', '第二部分的内容'];
    var offset = 0;
    final chapters = <Chapter>[];
    final titles = ['第一部分', '择善', '第二部分'];
    final levels = [1, 2, 1];
    for (var i = 0; i < texts.length; i++) {
      chapters.add(
        Chapter(
          id: 'n$i',
          bookId: 'nested',
          index: i,
          title: titles[i],
          startOffset: offset,
          endOffset: offset + texts[i].length,
          contentText: texts[i],
          level: levels[i],
        ),
      );
      offset += texts[i].length;
    }
    await ChapterRepository(db).replaceForBook('nested', chapters);
    await pumpReader(tester, 'nested');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final partTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '第一部分'),
    );
    final sectionTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '择善'),
    );
    expect(
      partTile.contentPadding,
      const EdgeInsetsDirectional.only(start: 16, end: 16),
    );
    expect(
      sectionTile.contentPadding,
      const EdgeInsetsDirectional.only(start: 40, end: 16),
    );

    final partText = tester.widget<Text>(find.text('第一部分'));
    final sectionText = tester.widget<Text>(find.text('择善'));
    expect(
      sectionText.style?.fontSize,
      lessThan(partText.style?.fontSize ?? 0),
    );

    await tester.tap(find.text('择善'));
    await tester.pumpAndSettle();
    expect(find.textContaining('择善的内容'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('styles a level-one chapter heading above body text', (
    tester,
  ) async {
    await seedHeadingBook(
      id: 'h1',
      titles: ['第一部分'],
      levels: [1],
      texts: ['第一部分\n正文一。'],
    );
    await pumpReader(tester, 'h1');

    final heading = spanWithText(tester, '第一部分');
    final body = renderedSpans(tester).firstWhere(
      (span) => span.text?.contains('正文一。') ?? false,
    );
    expect(heading.style?.fontSize, 27);
    expect(heading.style?.fontWeight, FontWeight.w700);
    expect(body.style?.fontSize, 18);
    expect(body.style?.fontWeight, isNot(FontWeight.w700));
    await disposeApp(tester);
  });

  testWidgets('styles a level-two section heading between part and body', (
    tester,
  ) async {
    await seedHeadingBook(
      id: 'h2',
      titles: ['择善'],
      levels: [2],
      texts: ['择善\n正文二。'],
    );
    await pumpReader(tester, 'h2');

    final heading = spanWithText(tester, '择善');
    final body = renderedSpans(tester).firstWhere(
      (span) => span.text?.contains('正文二。') ?? false,
    );
    expect(heading.style?.fontSize, closeTo(21.6, 0.01));
    expect(heading.style?.fontWeight, FontWeight.w600);
    expect(body.style?.fontSize, 18);
    await disposeApp(tester);
  });

  testWidgets('styles a heading that carries a footnote marker', (
    tester,
  ) async {
    await seedHeadingBook(
      id: 'h3',
      titles: ['耶和华必预备'],
      levels: [2],
      texts: ['耶和华必预备[8]\n正文三。'],
    );
    await pumpReader(tester, 'h3');

    final heading = spanWithText(tester, '耶和华必预备[8]');
    expect(heading.style?.fontSize, closeTo(21.6, 0.01));
    await disposeApp(tester);
  });

  testWidgets('leaves a first line alone when it is not the chapter title', (
    tester,
  ) async {
    await seedHeadingBook(
      id: 'h4',
      titles: ['第一章'],
      levels: [1],
      texts: ['正文直接开始。\n下一段。'],
    );
    await pumpReader(tester, 'h4');

    final first = renderedSpans(tester).first;
    expect(first.text, '正文直接开始。\n下一段。');
    expect(first.style?.fontSize, 18);
    expect(first.style?.fontWeight, isNot(FontWeight.w700));
    await disposeApp(tester);
  });

  testWidgets('shows a message when the book has no chapters', (tester) async {
    await pumpReader(tester, 'b2');
    expect(find.text('这本书暂时没有可显示的章节'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('bookmark icon adds a bookmark for the current page', (
    tester,
  ) async {
    await pumpReader(tester, 'b1');
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tester.tap(find.byTooltip('书签'));
    await settleAfterIo(tester);

    expect(find.text('已添加书签'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    final stored = await storedBookmarks(tester);
    expect(stored, hasLength(1));
    expect(stored!.single.chapterId, 'c1');
    expect(stored.single.type, AnnotationType.bookmark);
    expect(stored.single.anchorStart, inInclusiveRange(6, 12));
    await disposeApp(tester);
  });

  testWidgets('bookmark icon toggles off an existing bookmark', (tester) async {
    await seedBookmark(chapterId: 'c1', anchorStart: 8);
    await pumpReader(tester, 'b1');
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byTooltip('书签'));
    await settleAfterIo(tester);

    expect(find.text('已取消书签'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(await storedBookmarks(tester), isEmpty);
    await disposeApp(tester);
  });

  testWidgets('keeps one bookmark per page inside a chapter', (tester) async {
    await seedLongBook(lines: 200);
    await pumpReader(tester, 'long');

    await tester.tap(find.byTooltip('书签'));
    await settleAfterIo(tester);
    await tapNextZone(tester);
    await tester.tap(find.byTooltip('书签'));
    await settleAfterIo(tester);

    var stored = await storedBookmarks(tester, bookId: 'long');
    expect(stored, hasLength(2));
    expect(stored!.map((bookmark) => bookmark.chapterId).toSet(), {'long-c0'});
    expect(stored[0].anchorStart, lessThan(stored[1].anchorStart));

    await tapNextZone(tester);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tapPrevZone(tester);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await tester.tap(find.byTooltip('书签'));
    await settleAfterIo(tester);
    stored = await storedBookmarks(tester, bookId: 'long');
    expect(stored, hasLength(1));
    await disposeApp(tester);
  });

  testWidgets('a spread bookmark targets the left page', (tester) async {
    await seedLongBook(lines: 200);
    useWideWindow(tester);
    await pumpReader(tester, 'long');

    await tapNextZone(tester);
    await tapNextZone(tester);
    final leftText = firstPaneText(tester);
    await tester.tap(find.byTooltip('书签'));
    await settleAfterIo(tester);

    final text = (await ChapterRepository(db).getContent('long', 0))!;
    final stored = await storedBookmarks(tester, bookId: 'long');
    expect(stored, hasLength(1));
    expect(stored!.single.anchorStart, text.indexOf(leftText));
    await disposeApp(tester);
  });

  testWidgets('a bookmark survives a font change and still lands', (
    tester,
  ) async {
    await seedLongBook(lines: 200);
    await pumpReader(tester, 'long');

    await tapNextZone(tester);
    await tapNextZone(tester);
    final anchorText = pageText(tester).substring(0, 10);
    await tester.tap(find.byTooltip('书签'));
    await settleAfterIo(tester);
    final before = await storedBookmarks(tester, bookId: 'long');
    expect(before, hasLength(1));

    await tapNextZone(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(150, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 80));
    await tester.pumpAndSettle();

    expect(pageText(tester), isNot(contains(anchorText)));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.byTooltip('删除书签'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();

    expect(pageText(tester), contains(anchorText));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    final after = await storedBookmarks(tester, bookId: 'long');
    expect(after, hasLength(1));
    expect(after!.single.anchorStart, before!.single.anchorStart);
    await disposeApp(tester);
  });

  testWidgets('drawer lists bookmarks and jumps to the chapter', (
    tester,
  ) async {
    await seedBookmark(id: 'bm3', chapterId: 'c2', anchorStart: 13);
    await pumpReader(tester, 'b1');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();

    final bookmarkTile = find.ancestor(
      of: find.text('72%'),
      matching: find.byType(ListTile),
    );
    expect(bookmarkTile, findsOneWidget);
    expect(
      find.descendant(of: bookmarkTile, matching: find.text('第3章')),
      findsOneWidget,
    );

    await tester.tap(bookmarkTile);
    await tester.pumpAndSettle();
    expect(find.textContaining('第三章的内容'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('drawer shows an empty state without bookmarks', (tester) async {
    await pumpReader(tester, 'b1');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();

    expect(find.text('还没有书签'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('deleting a bookmark from the drawer removes it', (tester) async {
    await seedBookmark(chapterId: 'c1', anchorStart: 8);
    await pumpReader(tester, 'b1');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除书签'));
    await settleAfterIo(tester);

    expect(await storedBookmarks(tester), isEmpty);
    expect(find.text('还没有书签'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets(
    'jumping to a bookmark in an unloaded chapter keeps its position',
    (tester) async {
      final anchorStart = await seedTwoChapterBook();
      await seedBookmark(
        id: 'bm2',
        bookId: 'jb',
        chapterId: 'jb-c1',
        anchorStart: anchorStart,
      );
      await pumpReader(tester, 'jb');

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二章'));
      await tester.pumpAndSettle();
      await settleAfterIo(tester);

      expect(find.textContaining('乙第'), findsWidgets);
      expect(footerText(tester), isNot(startsWith('第 1 /')));
      await disposeApp(tester);
    },
  );

  testWidgets('a newly pumped reader shows a bookmark seeded in the DB', (
    tester,
  ) async {
    await seedBookmark(chapterId: 'c1', anchorStart: 8);
    await pumpReader(tester, 'b1');

    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('renders a stored highlight with its colour', (tester) async {
    await seedHighlight(
      chapterId: 'c1',
      anchorStart: 8,
      anchorEnd: 10,
      color: 'green',
    );
    await pumpReader(tester, 'b1');

    final highlighted = renderedSpans(tester)
        .where((span) => span.style?.backgroundColor != null)
        .toList();
    expect(highlighted, hasLength(1));
    expect(highlighted.single.text, '章的');
    expect(
      highlighted.single.style!.backgroundColor,
      highlightColorFor('green'),
    );
    await disposeApp(tester);
  });

  testWidgets('renders a stored note with a dotted underline', (tester) async {
    await seedHighlight(
      chapterId: 'c1',
      anchorStart: 8,
      anchorEnd: 10,
      type: AnnotationType.note,
      color: null,
      noteText: '这里要再想想',
    );
    await pumpReader(tester, 'b1');

    final note = renderedSpans(tester)
        .where(
          (span) => span.style?.decorationStyle == TextDecorationStyle.dotted,
        )
        .single;
    expect(note.text, '章的');
    expect(note.style!.decoration, TextDecoration.underline);
    expect(note.style!.backgroundColor, isNull);
    await disposeApp(tester);
  });

  testWidgets('ignores highlights that belong to another chapter', (
    tester,
  ) async {
    await seedHighlight(
      chapterId: 'c0',
      anchorStart: 1,
      anchorEnd: 3,
      color: 'pink',
    );
    await pumpReader(tester, 'b1');

    final highlighted = renderedSpans(tester)
        .where((span) => span.style?.backgroundColor != null)
        .toList();
    expect(highlighted, isEmpty);
    await disposeApp(tester);
  });

  testWidgets('opens the annotations page and jumps to a selected item', (
    tester,
  ) async {
    await seedHighlight(
      chapterId: 'c0',
      anchorStart: 2,
      anchorEnd: 5,
      selectedText: '章的内',
    );
    await pumpReader(tester, 'b1');
    expect(find.textContaining('第二章的内容'), findsOneWidget);

    await tester.tap(find.byTooltip('标注'));
    await tester.pumpAndSettle();
    expect(find.text('章的内'), findsOneWidget);
    expect(find.text('第1章'), findsOneWidget);

    await tester.tap(find.text('章的内'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第一章的内容'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('uses the serif reading typography by default', (tester) async {
    await pumpReader(tester, 'b1');

    final first = renderedSpans(tester).first;
    expect(first.style?.fontSize, 18);
    expect(first.style?.height, 1.8);
    expect(first.style?.fontFamily, 'Source Han Serif SC');
    expect(first.style?.fontFamilyFallback, contains('Georgia'));
    await disposeApp(tester);
  });

  testWidgets('uses the approved reading colours', (tester) async {
    await pumpReader(tester, 'b1');
    expect(renderedSpans(tester).first.style?.color, const Color(0xFF3B4048));
    await disposeApp(tester);

    await SettingsRepository(db).set('reader.background', 'dark');
    await pumpReader(tester, 'b1');
    expect(renderedSpans(tester).first.style?.color, const Color(0xFFC6CAD1));
    await disposeApp(tester);
  });

  testWidgets('caps the reading column at 720 logical pixels', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    tester.binding.handleMetricsChanged();
    await SettingsRepository(db).set('reader.spread', 'single');

    final text = List.filled(400, '这是一段足够长的正文内容').join();
    await BookRepository(db).upsert(
      Book(
        id: 'wide',
        title: '宽屏',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/wide.txt',
        addedAt: DateTime(2026, 1, 5),
      ),
    );
    await ChapterRepository(db).replaceForBook('wide', [
      Chapter(
        id: 'wide-c0',
        bookId: 'wide',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: text.length,
        contentText: text,
      ),
    ]);
    await pumpReader(tester, 'wide');

    expect(
      tester.getSize(find.byType(SelectableText)).width,
      lessThanOrEqualTo(720),
    );
    await disposeApp(tester);
  });

  testWidgets('shows the book title and the footer page counter', (
    tester,
  ) async {
    await pumpReader(tester, 'b1');
    expect(find.textContaining('测试小说 · 第2章'), findsOneWidget);
    expect(footerText(tester), startsWith('第 1 / '));
    await disposeApp(tester);
  });

  Future<String> seedMarkerProgress() async {
    await seedLongBook();
    final text = (await ChapterRepository(db).getContent('long', 0))!;
    final marker = text.indexOf('第40段');
    await ProgressRepository(db).save(
      ReadingProgress(
        bookId: 'long',
        anchor: ReadingAnchor(charOffset: marker),
        percent: marker / text.length,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    return text;
  }

  int chapterPageCount(WidgetTester tester) {
    return int.parse(
      RegExp(r'^第 \d+ / (\d+) 页').firstMatch(footerText(tester))!.group(1)!,
    );
  }

  testWidgets('keeps the page start when the font size changes', (
    tester,
  ) async {
    await seedMarkerProgress();
    await pumpReader(tester, 'long');
    final anchorText = pageText(tester).substring(0, 10);
    final before = chapterPageCount(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(150, 0));
    await tester.pumpAndSettle();

    expect(pageText(tester), contains(anchorText));
    expect(chapterPageCount(tester), greaterThan(before));
    await disposeApp(tester);
  });

  testWidgets('keeps the page start when the window is resized', (
    tester,
  ) async {
    await seedMarkerProgress();
    await pumpReader(tester, 'long');
    final anchorText = pageText(tester).substring(0, 10);
    final before = chapterPageCount(tester);

    addTearDown(tester.view.reset);
    final view = tester.view;
    view.physicalSize = Size(
      view.physicalSize.width,
      view.physicalSize.height * 1.2,
    );
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();

    expect(pageText(tester), contains(anchorText));
    expect(chapterPageCount(tester), lessThan(before));
    await disposeApp(tester);
  });

  testWidgets('keeps the page start when the rail is pinned', (tester) async {
    await seedMarkerProgress();
    await pumpReader(tester, 'long');
    final anchorText = pageText(tester).substring(0, 10);

    await tester.tap(find.byTooltip('固定左栏'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-rail-pinned')), findsOneWidget);
    expect(pageText(tester), startsWith(anchorText));
    await disposeApp(tester);
  });

  testWidgets('the illustration entry asks which text to use', (tester) async {
    await pumpReader(tester, 'b1');
    await tester.tap(find.byTooltip('固定左栏'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rail-illustration')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('illustration-source-sheet')), findsOneWidget);
    expect(find.text('从哪里取文生图？'), findsOneWidget);
    expect(find.byKey(const Key('illustration-source-page')), findsOneWidget);
    expect(
      find.byKey(const Key('illustration-source-nearby')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('illustration-source-chapter')),
      findsOneWidget,
    );
    await disposeApp(tester);
  });

  testWidgets('choosing the chapter fills the composer with its text',
      (tester) async {
    await pumpReader(tester, 'b1');
    await tester.tap(find.byTooltip('固定左栏'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rail-illustration')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('illustration-source-chapter')));
    await tester.pumpAndSettle();

    expect(find.byType(IllustrationComposerPage), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '第二章的内容');
    await disposeApp(tester);
  });

  testWidgets('selecting text offers to turn it into an illustration',
      (tester) async {
    await pumpReader(tester, 'b1');

    await tester.longPress(find.byType(SelectableText).first);
    await tester.pumpAndSettle();

    expect(find.text('生成插画'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('selecting text offers to quote it into the companion',
      (tester) async {
    await pumpReader(tester, 'b1');

    await tester.longPress(find.byType(SelectableText).first);
    await tester.pumpAndSettle();

    expect(find.text('引用'), findsOneWidget);

    await tester.tap(find.text('引用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage)),
    );
    final quotes = container.read(companionQuotesProvider);
    expect(quotes, hasLength(1));
    expect(quotes.single.trim(), isNotEmpty);
    await disposeApp(tester);
  });

  testWidgets('a background illustration reports progress and result',
      (tester) async {
    final completer = Completer<IllustrationResult>();
    await pumpReader(
      tester,
      'b1',
      overrides: [
        illustrationConfigProvider.overrideWith((ref) async => _jobConfig),
        llmConfigProvider.overrideWith((ref) async => _jobLlm),
        illustrationServiceFactoryProvider.overrideWithValue(
          (_) => _ReaderFakeService((onStage) {
            onStage?.call(IllustrationStage.planning);
            return completer.future;
          }),
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage)),
    );

    container.read(illustrationJobProvider.notifier).start(
          text: '第一章的内容',
          label: '测试 · 整章',
        );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('reader-illustration-job')), findsOneWidget);
    expect(find.textContaining('插画生成中'), findsOneWidget);

    completer.complete(_jobResult());
    await tester.pump();
    await tester.pump();

    expect(find.text('插画已生成'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-illustration-job-open')));
    await tester.pumpAndSettle();

    expect(find.byType(IllustrationComposerPage), findsOneWidget);
    expect(find.text('成品预览'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('a running illustration opens its progress and can be stopped',
      (tester) async {
    final completer = Completer<IllustrationResult>();
    await pumpReader(
      tester,
      'b1',
      overrides: [
        illustrationConfigProvider.overrideWith((ref) async => _jobConfig),
        llmConfigProvider.overrideWith((ref) async => _jobLlm),
        illustrationServiceFactoryProvider.overrideWithValue(
          (_) => _ReaderFakeService((onStage) {
            onStage?.call(IllustrationStage.planning);
            return completer.future;
          }),
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage)),
    );
    container.read(illustrationJobProvider.notifier).start(
          text: '第一章的内容',
          label: '测试 · 整章',
        );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-illustration-job-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(IllustrationComposerPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(IllustrationComposerPage),
        matching: find.textContaining('正在分析文段'),
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('reader-illustration-job-stop')));
    await tester.pump();

    expect(find.byKey(const Key('reader-illustration-job')), findsNothing);
    expect(container.read(illustrationJobProvider), isNull);
    await disposeApp(tester);
  });

  testWidgets('TOC jumps land on the chapter first page', (tester) async {
    await seedTwoChapterBook();
    await pumpReader(tester, 'jb');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();

    expect(find.textContaining('跳转测试 · 第二章'), findsOneWidget);
    expect(footerText(tester), startsWith('第 1 /'));
    await disposeApp(tester);
  });

  testWidgets('bookmark jumps land on the page containing the anchor', (
    tester,
  ) async {
    await seedTwoChapterBook();
    final text0 = (await ChapterRepository(db).getContent('jb', 0))!;
    final text1 = (await ChapterRepository(db).getContent('jb', 1))!;
    final marker = text0.length + text1.indexOf('乙第30段');
    await seedBookmark(
      id: 'bm-mid',
      bookId: 'jb',
      chapterId: 'jb-c1',
      anchorStart: marker,
    );
    await pumpReader(tester, 'jb');

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();

    expect(find.textContaining('乙第30段'), findsOneWidget);
    expect(footerText(tester), isNot(startsWith('第 1 /')));
    await disposeApp(tester);
  });

  testWidgets('annotation jumps land on the page containing the highlight', (
    tester,
  ) async {
    await seedMarkerProgress();
    final text = (await ChapterRepository(db).getContent('long', 0))!;
    final marker = text.indexOf('第40段');
    await seedHighlight(
      bookId: 'long',
      chapterId: 'long-c0',
      anchorStart: marker,
      anchorEnd: marker + 4,
      selectedText: '第40段',
    );
    await pumpReader(tester, 'long');

    await tester.tap(find.byTooltip('标注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第40段'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第40段'), findsOneWidget);
    expect(footerText(tester), isNot(startsWith('第 1 /')));
    await disposeApp(tester);
  });

  testWidgets('fills in the whole-book total and cumulative page', (
    tester,
  ) async {
    await pumpReader(tester, 'b1');
    await settleBookCount(tester);

    expect(
      footerText(tester),
      matches(RegExp(r'^第 1 / 1 页 · 全书 2 / 3 页$')),
    );
    await disposeApp(tester);
  });

  testWidgets('advances the whole-book page across a chapter boundary', (
    tester,
  ) async {
    await seedTwoChapterBook();
    await pumpReader(tester, 'jb');
    await settleBookCount(tester);

    final firstCount = int.parse(
      RegExp(r'^第 \d+ / (\d+) 页').firstMatch(footerText(tester))!.group(1)!,
    );
    for (var i = 1; i < firstCount; i++) {
      await tapNextZone(tester);
    }
    expect(footerText(tester), contains('全书 $firstCount / '));

    await tapNextZone(tester);
    expect(footerText(tester), startsWith('第 1 /'));
    expect(footerText(tester), contains('全书 ${firstCount + 1} / '));
    await disposeApp(tester);
  });

  testWidgets('recounts after a font change without stale totals', (
    tester,
  ) async {
    await seedLongBook();
    await pumpReader(tester, 'long');
    await settleBookCount(tester);
    final before = int.parse(
      RegExp(r'全书 \d+ / (\d+) 页$').firstMatch(footerText(tester))!.group(1)!,
    );

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(150, 0));
    await tester.pumpAndSettle();
    await settleBookCount(tester);

    final after = int.parse(
      RegExp(r'全书 \d+ / (\d+) 页$').firstMatch(footerText(tester))!.group(1)!,
    );
    expect(after, greaterThan(before));
    await disposeApp(tester);
  });

  testWidgets('defaults to a two-page spread on a wide window', (tester) async {
    await seedLongBook();
    useWideWindow(tester);
    await pumpReader(tester, 'long');

    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(spreadFooterText(tester), startsWith('第 1–2 / '));
    expect(spreadFooterText(tester), contains('全书 '));
    await disposeApp(tester);
  });

  testWidgets('spread pages fit the style they are rendered with', (
    tester,
  ) async {
    final paragraph = List.filled(200, 'a').join();
    final text = List.filled(120, paragraph).join('\n');
    await BookRepository(db).upsert(
      Book(
        id: 'spread-fit',
        title: '宽度测试',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/spread-fit.txt',
        addedAt: DateTime(2026, 1, 4),
      ),
    );
    await ChapterRepository(db).replaceForBook('spread-fit', [
      Chapter(
        id: 'spread-fit-c0',
        bookId: 'spread-fit',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: text.length,
        contentText: text,
      ),
    ]);
    addTearDown(tester.view.reset);
    // 1304 logical pixels gives a 600px pane: the paginator fits 33 glyphs
    // at 18px each, but the rendered SelectableText inherits the theme's
    // 0.25 letterSpacing and fits only 32.
    tester.view.physicalSize = const Size(1304, 900);
    tester.view.devicePixelRatio = 1;
    tester.binding.handleMetricsChanged();
    await pumpReader(tester, 'spread-fit');

    final panes = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .toList();
    expect(panes, hasLength(2));
    for (final pane in panes) {
      expect(
        paneTextBottom(tester, pane),
        lessThanOrEqualTo(paneClipHeight(tester, pane) + 0.5),
      );
    }
    await disposeApp(tester);
  });

  testWidgets('advances two pages at a time in a spread', (tester) async {
    await seedLongBook(lines: 200);
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

    tester.view.physicalSize = const Size(1400, 900);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(2));
    await disposeApp(tester);
  });

  testWidgets('shrinking and widening keeps the spread position', (
    tester,
  ) async {
    await seedLongBook(lines: 200);
    useWideWindow(tester);
    await pumpReader(tester, 'long');

    await tapNextZone(tester);
    await tapNextZone(tester);
    final anchor = spreadPageText(tester).substring(0, 10);
    final footer = spreadFooterText(tester);

    tester.view.physicalSize = const Size(800, 600);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1400, 900);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();

    expect(spreadFooterText(tester), footer);
    expect(spreadPageText(tester), contains(anchor));
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
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '下一页'))
          .onPressed,
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
    final footer = spreadFooterText(tester);
    final range = RegExp(r'^第 (\d+)–(\d+) / (\d+) 页').firstMatch(footer);
    if (range != null) {
      expect(range.group(2), range.group(3));
    } else {
      final lone = RegExp(r'^第 (\d+) / (\d+) 页').firstMatch(footer)!;
      expect(lone.group(1), lone.group(2));
    }
    await disposeApp(tester);
  });

  testWidgets('a saved position opens the spread containing it', (
    tester,
  ) async {
    await seedLongBook(lines: 200);
    final text = (await ChapterRepository(db).getContent('long', 0))!;
    final marker = text.indexOf('第80段');
    await ProgressRepository(db).save(
      ReadingProgress(
        bookId: 'long',
        anchor: ReadingAnchor(charOffset: marker),
        percent: marker / text.length,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    useWideWindow(tester);
    await pumpReader(tester, 'long');

    expect(find.textContaining('第80段'), findsOneWidget);
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

  group('inline illustrations', () {
    late Directory temp;
    late BookStorage storage;

    const illustratedText = '第0段：开头文字。\n第1段：中间文字。\n第2段：结尾文字。';

    final kTinyPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('reader_illustration_test');
      storage = BookStorage(Directory('${temp.path}/books'));
    });

    tearDown(() async {
      try {
        await temp.delete(recursive: true);
      } on FileSystemException {
        // Decoded image files can stay locked briefly on Windows.
      }
    });

    Future<void> pumpIllustrated(WidgetTester tester, String bookId) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            bookStorageProvider.overrideWith((ref) async => storage),
          ],
          child: MaterialApp(home: ReaderPage(bookId: bookId)),
        ),
      );
      // The illustration manifest is real file IO, so alternate fake frames
      // with real-time slices until the provider resolves.
      for (var round = 0; round < 16; round++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pump();
    }

    Future<void> seedIllustrated({
      int offset = '第0段：开头文字。\n'.length,
    }) async {
      await BookRepository(db).upsert(
        Book(
          id: 'ill',
          title: '插图本',
          author: '',
          format: BookFormat.epub,
          sourcePath: 'C:/books/ill.epub',
          addedAt: DateTime(2026, 1, 1),
        ),
      );
      await ChapterRepository(db).replaceForBook('ill', [
        Chapter(
          id: 'ill-c0',
          bookId: 'ill',
          index: 0,
          title: '第一章',
          startOffset: 0,
          endOffset: illustratedText.length,
          contentText: illustratedText,
        ),
      ]);
      await storage.saveIllustrations('ill', [
        (
          chapterIndex: 0,
          offset: offset,
          width: 2,
          height: 1,
          bytes: kTinyPng,
          extension: 'png',
        ),
      ]);
    }

    testWidgets('an illustrated page renders text fragments around the image', (
      tester,
    ) async {
      await tester.runAsync(seedIllustrated);
      await pumpIllustrated(tester, 'ill');

      expect(
        find.byKey(const ValueKey('reader-illustration-0')),
        findsOneWidget,
      );
      final texts = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.textSpan!.toPlainText())
          .toList();
      expect(texts.length, greaterThanOrEqualTo(2));
      expect(texts.join(), contains('开头文字'));
      expect(texts.join(), contains('中间文字'));
      await disposeApp(tester);
    });

    testWidgets('tapping an image opens the viewer instead of turning the page', (
      tester,
    ) async {
      await tester.runAsync(seedIllustrated);
      await pumpIllustrated(tester, 'ill');
      final footer = tester
          .widget<Text>(find.byKey(const Key('reader-footer')))
          .data;

      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('reader-illustration-0'))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('illustration-viewer')), findsOneWidget);

      await tester.tap(find.byKey(const Key('illustration-viewer-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('illustration-viewer')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('reader-footer'))).data,
        footer,
      );
      await disposeApp(tester);
    });

    testWidgets('pages without images keep a single SelectableText', (
      tester,
    ) async {
      await pumpReader(tester, 'b1');
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await disposeApp(tester);
    });

    testWidgets('a spread shows an illustration on only one pane', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(seedIllustrated);
      await pumpIllustrated(tester, 'ill');

      expect(
        find.byKey(const ValueKey('reader-illustration-0')),
        findsOneWidget,
      );
      await disposeApp(tester);
    });

    testWidgets('an illustrated page keeps its content inside the clip', (
      tester,
    ) async {
      await tester.runAsync(seedIllustrated);
      await pumpIllustrated(tester, 'ill');

      final image = find.byKey(const ValueKey('reader-illustration-0'));
      final content = tester
          .renderObject<RenderBox>(
            find.ancestor(of: image, matching: find.byType(Column)).first,
          )
          .size
          .height;
      final clip = tester
          .renderObject<RenderBox>(
            find.ancestor(of: image, matching: find.byType(ClipRect)).first,
          )
          .size
          .height;
      expect(content, lessThanOrEqualTo(clip + 0.5));
      await disposeApp(tester);
    });
  });

  group('comic reader', () {
    late Directory temp;
    late BookStorage storage;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('reader_comic_test');
      storage = BookStorage(temp);
      await storage.saveComicPages('manga', [
        (bytes: const [1, 2, 3], extension: 'png', title: '封面'),
        (bytes: const [4, 5, 6], extension: 'png', title: '第一话'),
        (bytes: const [7, 8, 9], extension: 'png', title: '第二话'),
      ]);
      await BookRepository(db).upsert(
        Book(
          id: 'manga',
          title: '测试漫画',
          author: '',
          format: BookFormat.epub,
          sourcePath: 'C:/books/manga.epub',
          addedAt: DateTime(2026, 1, 6),
          comic: true,
        ),
      );
    });

    tearDown(() async {
      try {
        await temp.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the decoded page files open.
      }
    });

    Future<void> pumpComic(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            bookStorageProvider.overrideWith((ref) async => storage),
          ],
          child: const MaterialApp(home: ReaderPage(bookId: 'manga')),
        ),
      );
      // The page listing is real file IO, so alternate fake frames with
      // real-time slices until the provider resolves.
      for (var round = 0; round < 16; round++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pump();
    }

    Future<void> pumpComicWide(WidgetTester tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      tester.binding.handleMetricsChanged();
      await pumpComic(tester);
    }

    IconButton toolbarButton(WidgetTester tester, String tooltip) {
      return tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
    }

    testWidgets('renders the first page and the page counter', (tester) async {
      await pumpComic(tester);

      expect(find.byKey(const Key('comic-page-view')), findsOneWidget);
      expect(find.text('测试漫画 · 第 1 / 3 页'), findsOneWidget);
      expect(find.text('第 1 / 3 页 · 33%'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('comic-page-0'))),
        tester.getSize(find.byKey(const Key('comic-page-view'))),
      );
      await disposeApp(tester);
    });

    testWidgets('next and previous buttons move between pages', (tester) async {
      await pumpComic(tester);

      await tester.tap(find.widgetWithText(TextButton, '下一页'));
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 2 / 3 页'), findsOneWidget);
      expect(find.text('第 2 / 3 页 · 67%'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '上一页'));
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 1 / 3 页'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('annotation-only toolbar entries are disabled', (
      tester,
    ) async {
      await pumpComic(tester);

      for (final tooltip in const [
        '漫画暂不支持标注',
        '漫画暂不支持陪读',
        '漫画暂不支持设置',
      ]) {
        expect(toolbarButton(tester, tooltip).onPressed, isNull);
      }
      expect(toolbarButton(tester, '目录').onPressed, isNotNull);
      expect(toolbarButton(tester, '书签').onPressed, isNotNull);
      expect(toolbarButton(tester, '固定左栏').onPressed, isNotNull);
      await disposeApp(tester);
    });

    testWidgets('bookmarks the current page and toggles it off', (tester) async {
      await pumpComic(tester);

      await tester.tap(find.byTooltip('书签'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(
        () => AnnotationRepository(db).getForBook(
          'manga',
          type: AnnotationType.bookmark,
        ),
      );
      expect(saved, hasLength(1));
      expect(saved!.single.anchorStart, 1);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      await tester.tap(find.byTooltip('书签'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final cleared = await tester.runAsync(
        () => AnnotationRepository(db).getForBook(
          'manga',
          type: AnnotationType.bookmark,
        ),
      );
      expect(cleared, isEmpty);
      await disposeApp(tester);
    });

    testWidgets('the bookmark tab jumps to a bookmarked page', (tester) async {
      await AnnotationRepository(db).upsert(
        Annotation(
          id: 'bm',
          bookId: 'manga',
          type: AnnotationType.bookmark,
          anchorStart: 2,
          createdAt: DateTime(2026, 1, 6),
          updatedAt: DateTime(2026, 1, 6),
        ),
      );
      await pumpComic(tester);

      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      expect(find.text('第一话'), findsOneWidget);

      await tester.tap(find.text('第一话'));
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 2 / 3 页'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('the left rail can be pinned while reading a comic', (
      tester,
    ) async {
      await pumpComic(tester);

      await tester.tap(find.byTooltip('固定左栏'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-rail-pinned')), findsOneWidget);
      expect(find.byTooltip('应用设置'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('rail-companion')))
            .onPressed,
        isNull,
      );
      await disposeApp(tester);
    });

    testWidgets('resumes from the saved page', (tester) async {
      await ProgressRepository(db).save(
        ReadingProgress(
          bookId: 'manga',
          anchor: const ReadingAnchor.page(2),
          percent: 2 / 3,
          updatedAt: DateTime(2026, 1, 6),
        ),
      );
      await pumpComic(tester);

      expect(find.text('测试漫画 · 第 2 / 3 页'), findsOneWidget);
      expect(find.text('第 2 / 3 页 · 67%'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('the page drawer lists titles and jumps to a page', (
      tester,
    ) async {
      await pumpComic(tester);

      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      expect(find.text('封面'), findsOneWidget);
      expect(find.text('第一话'), findsOneWidget);
      expect(find.text('第二话'), findsOneWidget);

      await tester.tap(find.text('第一话'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comic-page-view')), findsOneWidget);
      expect(find.text('测试漫画 · 第 2 / 3 页'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('progress survives leaving and reopening the reader', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            bookStorageProvider.overrideWith((ref) async => storage),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReaderPage(bookId: 'manga'),
                      ),
                    ),
                    child: const Text('打开漫画'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> settleComicIo() async {
        for (var round = 0; round < 16; round++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        await tester.pump();
      }

      await tester.tap(find.text('打开漫画'));
      await settleComicIo();
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 1 / 3 页'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '下一页'));
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 2 / 3 页'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      await tester.tap(find.text('打开漫画'));
      await settleComicIo();
      expect(find.text('测试漫画 · 第 2 / 3 页'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('paging saves the page progress', (tester) async {
      await pumpComic(tester);

      await tester.tap(find.widgetWithText(TextButton, '下一页'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '下一页'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      final saved = await tester.runAsync(
        () => ProgressRepository(db).get('manga'),
      );
      expect(saved!.anchor.page, 3);
      expect(saved.percent, closeTo(1.0, 0.001));
      await disposeApp(tester);
    });

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

      await tester.tap(find.widgetWithText(TextButton, '下一页'));
      await tester.pumpAndSettle();
      expect(find.text('测试漫画 · 第 3 / 3 页'), findsOneWidget);
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

      await tester.tap(find.byTooltip('固定左栏'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-rail-pinned')), findsNothing);
      expect(find.byKey(const Key('comic-page-0')), findsOneWidget);
      expect(find.byKey(const Key('comic-page-1')), findsOneWidget);
      await disposeApp(tester);
    });
  });

  group('companion avatar', () {
    testWidgets('hugs the right margin when the window is wide', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpReader(tester, 'b1');

      final page = tester.getRect(find.byKey(const Key('reader-page')));
      final avatar = tester.getRect(find.byKey(const Key('companion-avatar')));
      final columnRight = page.center.dx + 360; // 720-wide column, centred
      expect(avatar.left, greaterThanOrEqualTo(columnRight));
      expect(avatar.right, lessThanOrEqualTo(page.right));
      expect(avatar.bottom, lessThanOrEqualTo(page.bottom));
      expect(avatar.width / avatar.height, closeTo(0.75, 0.01));
      await disposeApp(tester);
    });

    testWidgets('stays on screen and shrinks in a narrow window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpReader(tester, 'b1');

      final page = tester.getRect(find.byKey(const Key('reader-page')));
      final avatar = tester.getRect(find.byKey(const Key('companion-avatar')));
      expect(avatar.height, 120);
      expect(avatar.right, lessThanOrEqualTo(360));
      expect(avatar.bottom, lessThanOrEqualTo(page.bottom));
      await disposeApp(tester);
    });

    testWidgets('tapping the avatar does not turn the page', (tester) async {
      await seedLongBook();
      await pumpReader(tester, 'long');

      String pageText() => tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText();
      final before = pageText();

      await tester.tap(find.byKey(const Key('companion-avatar')));
      await tester.pumpAndSettle();

      expect(pageText(), before);
      await disposeApp(tester);
    });

    testWidgets('flinches when the reader turns the page', (tester) async {
      await seedLongBook();
      await pumpReader(tester, 'long');
      final stage = tester.state<CompanionClipStageState>(
        find.byType(CompanionClipStage),
      );
      expect(stage.clip, companionIdleClip);

      await tester.tap(find.byKey(const Key('reader-next-zone')));
      await tester.pump();

      expect(stage.clip, companionSurpriseClip);
      await disposeApp(tester);
    });

    testWidgets('wears the pet clips', (tester) async {
      await pumpReader(tester, 'b1');

      final avatar = tester.widget<CompanionAvatar>(
        find.byType(CompanionAvatar),
      );
      expect(avatar.assetPath, isNull);
      expect(find.byType(CompanionClipStage), findsOneWidget);
      await disposeApp(tester);
    });
  });
}
