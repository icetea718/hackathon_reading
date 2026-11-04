import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../assistant/assistant_service.dart';
import '../../assistant/reading_context.dart';
import '../../assistant/translation_exception.dart';
import '../../assistant/translation_segmenter.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/annotation.dart';
import '../../domain/models/book.dart';
import '../../domain/models/book_illustration.dart';
import '../../illustration/illustration_models.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/comic_page.dart';
import '../../domain/models/reading_progress.dart';
import '../annotations/annotations_page.dart';
import '../companion/companion_chat.dart';
import '../companion/companion_chat_controller.dart';
import '../companion/companion_greeting.dart';
import '../companion/companion_panel.dart';
import '../companion/companion_presence.dart';
import '../illustration/illustration_composer_page.dart';
import '../illustration/illustration_jobs.dart';
import '../settings/settings_page.dart';
import 'annotation_spans.dart';
import 'chapter_paginator.dart';
import 'chapter_translation.dart';
import 'comic_toc_drawer.dart';
import 'illustration_source.dart';
import 'illustration_source_sheet.dart';
import 'illustration_viewer.dart';
import 'reader_position.dart';
import 'reader_providers.dart';
import 'reader_rail.dart';
import 'reader_settings_sheet.dart';
import 'reader_spread.dart';
import 'reader_top_bar.dart';
import 'toc_drawer.dart';
import 'translation_dialog.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.selectedText});

  final String selectedText;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _controller.text.trim();
    if (note.isEmpty) {
      setState(() => _error = '笔记内容不能为空');
      return;
    }
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加笔记'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.selectedText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(hintText: '写下你的想法', errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  static const _fontSizeKey = 'reader.fontSize';
  static const _lineHeightKey = 'reader.lineHeight';
  static const _backgroundKey = 'reader.background';
  static const _spreadKey = 'reader.spread';
  static const _railPinnedKey = 'reader.railPinned';
  static const _companionPanelWidth = 360.0;
  static const _companionDockMinWidth = 900.0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _chapterIndex = 0;
  int _pageIndex = 0;

  /// Ticks on every page turn so the companion can flinch.
  final ValueNotifier<int> _pageTurns = ValueNotifier<int>(0);
  int? _pendingOffset;
  ChapterPagination? _pagination;
  String? _paginationKey;
  String? _paginationChapterId;
  List<int>? _bookPageCounts;
  String? _bookPageCountsSignature;
  String? _bookPageSignature;
  final Map<String, List<int>> _bookPageCache = {};
  int _bookCountToken = 0;
  double _fontSize = 18;
  double _lineHeight = 1.8;
  ReaderBackground _background = ReaderBackground.light;
  ReaderSpread _spread = ReaderSpread.double;
  bool _doubleSpread = false;
  int? _pageEndIndex;
  int? _doubleAnchorOffset;
  bool _railPinned = false;
  bool _railVisible = false;
  bool _suppressHotzone = false;
  bool _restoreScheduled = false;
  bool _restored = false;
  bool _settingsDirty = false;
  Timer? _saveTimer;
  Timer? _settingsSaveTimer;
  Timer? _hideTimer;
  Timer? _comicSaveTimer;
  ReaderData? _cachedData;
  String _chapterText = '';
  String? _chapterTextChapterId;
  bool _translationVisible = false;
  bool _translationBusy = false;
  bool _translationActive = false;
  String? _translationChapterId;
  List<TranslationBlock> _translationBlocks = const [];
  final Map<String, List<TranslationBlock>> _translationCache = {};
  int _translationDone = 0;
  int _translationTotal = 0;
  int _translationToken = 0;
  ProgressRepository? _progressRepository;
  SettingsRepository? _settingsRepository;
  PageController? _comicController;
  int _comicPageIndex = 0;
  int _comicPageCount = 0;
  bool _comicInitialized = false;
  bool _comicDouble = false;
  bool _companionOpen = false;
  int? _companionChapterIndex;
  int? _companionLoadingIndex;
  String _companionChapterText = '';
  int _companionCharOffset = 0;
  int _companionLoadToken = 0;
  List<({GlobalKey key, String path})> _illustrationTargets = const [];
  int _illustrationSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsRepository = ref.read(settingsRepositoryProvider);
    _chatController = CompanionChatController(
      loadService: () => ref.read(assistantServiceProvider.future),
      loadPersona: () => ref.read(personaModeProvider),
    );
    // The stored voice loads asynchronously; chat should not open in the
    // default temper just because the reader was quick to click.
    unawaited(ref.read(personaModeProvider.notifier).ensureRestored());
    _loadReadingSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _settingsSaveTimer?.cancel();
    _hideTimer?.cancel();
    _comicSaveTimer?.cancel();
    _persistProgress();
    _persistComicProgress();
    _persistReadingSettings();
    _comicController?.dispose();
    _chatController.dispose();
    _pageTurns.dispose();
    super.dispose();
  }

  Future<void> _loadReadingSettings() async {
    final repository = _settingsRepository;
    if (repository == null) return;
    try {
      final values = await Future.wait([
        repository.get(_fontSizeKey),
        repository.get(_lineHeightKey),
        repository.get(_backgroundKey),
        repository.get(_railPinnedKey),
        repository.get(_spreadKey),
      ]);
      if (!mounted) return;
      final fontSize = double.tryParse(values[0] ?? '');
      final lineHeight = double.tryParse(values[1] ?? '');
      final background = _backgroundFromName(values[2]);
      final railPinned = values[3];
      final spreadName = values[4];
      if (fontSize == null &&
          lineHeight == null &&
          background == null &&
          railPinned == null &&
          spreadName == null) {
        return;
      }
      final chapters = _cachedData?.chapters ?? const <Chapter>[];
      final anchor = _restored ? _currentPageStartOffset(chapters) : null;
      setState(() {
        if (anchor != null) _pendingOffset = anchor;
        if (fontSize != null) _fontSize = fontSize.clamp(14.0, 28.0).toDouble();
        if (lineHeight != null) {
          _lineHeight = lineHeight.clamp(1.2, 2.0).toDouble();
        }
        if (background != null) _background = background;
        if (spreadName != null) _spread = readerSpreadFromName(spreadName);
        if (railPinned != null) _railPinned = railPinned == 'true';
      });
    } catch (_) {
      // Corrupt settings must not block reading.
    }
  }

  ReaderBackground? _backgroundFromName(String? name) {
    for (final value in ReaderBackground.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  void _scheduleSaveReadingSettings() {
    _settingsDirty = true;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(
      const Duration(milliseconds: 300),
      _persistReadingSettings,
    );
  }

  void _persistReadingSettings() {
    if (!_settingsDirty) return;
    final repository = _settingsRepository;
    if (repository == null) return;
    _settingsDirty = false;
    repository
        .set(_fontSizeKey, _fontSize.toString())
        .catchError((Object _) {});
    repository
        .set(_lineHeightKey, _lineHeight.toString())
        .catchError((Object _) {});
    repository.set(_backgroundKey, _background.name).catchError((Object _) {});
    repository.set(_spreadKey, _spread.name).catchError((Object _) {});
  }

  @override
  void didChangeMetrics() {
    if (!_restored) return;
    final chapters = _cachedData?.chapters ?? const <Chapter>[];
    final view = View.of(context);
    final width = view.physicalSize.width / view.devicePixelRatio;
    if (spreadApplies(_spread, width) && !_doubleSpread) {
      _pendingOffset ??= _doubleAnchorOffset;
    }
    _pendingOffset ??= _currentPageStartOffset(chapters);
  }

  void _scheduleProgressSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _persistProgress);
  }

  void _persistProgress() {
    if (!_restored) return;
    final repository = _progressRepository;
    if (repository == null) return;
    final progress = _currentProgress();
    if (progress == null) return;
    repository.save(progress).catchError((Object _) {});
  }

  ReadingProgress? _currentProgress() {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return null;

    final chapters = data.chapters;
    final index = _chapterIndex.clamp(0, chapters.length - 1);
    final chapter = chapters[index];
    final charOffset = _currentPageStartOffset(chapters) ?? chapter.startOffset;
    final total = chapters.last.endOffset;
    final percent = total <= 0
        ? 0.0
        : (charOffset / total).clamp(0.0, 1.0).toDouble();

    return ReadingProgress(
      bookId: widget.bookId,
      anchor: ReadingAnchor(charOffset: charOffset),
      percent: percent,
      updatedAt: DateTime.now(),
    );
  }

  int? _currentPageStartOffset(List<Chapter> chapters) {
    final pending = _pendingOffset;
    if (pending != null) return pending;
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return null;
    final index = _chapterIndex.clamp(0, data.chapters.length - 1);
    final chapter = data.chapters[index];
    final pagination = _pagination;
    if (pagination == null || _paginationChapterId != chapter.id) return null;
    return chapter.startOffset + pagination.pageAt(_pageIndex).start;
  }

  ChapterPagination? _validPagination(List<Chapter> chapters) {
    final index = _chapterIndex.clamp(0, chapters.length - 1);
    if (_paginationChapterId != chapters[index].id) return null;
    return _pagination;
  }

  void _startBookPageCount(
    PageLayout layout,
    List<Chapter> chapters,
    String signature,
    List<BookIllustration> illustrations,
  ) {
    final cached = _bookPageCache[signature];
    final token = ++_bookCountToken;
    if (cached != null) {
      setState(() {
        _bookPageCounts = cached;
        _bookPageCountsSignature = signature;
      });
      return;
    }
    setState(() {
      _bookPageCounts = null;
      _bookPageCountsSignature = null;
    });
    final repository = ref.read(chapterRepositoryProvider);
    countBookPages(
      chapters: chapters,
      layout: layout,
      loadChapter: (index) =>
          repository.getContent(widget.bookId, index).then((text) => text ?? ''),
      loadIllustrations: (index) async => [
        for (final image in illustrations)
          if (image.chapterIndex == index) image,
      ],
      onProgress: (counts) {
        if (!mounted ||
            token != _bookCountToken ||
            _bookPageSignature != signature) {
          return;
        }
        setState(() {
          _bookPageCounts = counts;
          _bookPageCountsSignature = signature;
        });
      },
      isCurrent: () =>
          mounted &&
          token == _bookCountToken &&
          _bookPageSignature == signature,
    ).then((counts) {
      if (!mounted ||
          token != _bookCountToken ||
          _bookPageSignature != signature) {
        return;
      }
      _bookPageCache[signature] = counts;
      setState(() {
        _bookPageCounts = counts;
        _bookPageCountsSignature = signature;
      });
    });
  }

  void _scheduleRestore(ReaderData data) {
    if (_restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (data.chapters.isNotEmpty) {
        final saved = data.progress?.anchor.charOffset;
        if (saved == null) {
          _pendingOffset = data.chapters.first.startOffset;
          setState(() => _chapterIndex = 0);
        } else {
          final location = locateAnchor(data.chapters, saved);
          _pendingOffset = saved;
          setState(() => _chapterIndex = location.chapterIndex);
        }
      } else {
        _restored = true;
      }

      final book = data.book;
      if (book != null) {
        final opened = Book(
          id: book.id,
          title: book.title,
          author: book.author,
          format: book.format,
          sourcePath: book.sourcePath,
          coverPath: book.coverPath,
          contentHash: book.contentHash,
          comic: book.comic,
          addedAt: book.addedAt,
          lastOpenedAt: DateTime.now(),
        );
        ref
            .read(bookRepositoryProvider)
            .upsert(opened)
            .catchError((Object _) {});
      }
    });
  }

  void _goToChapter(int index) {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    if (index < 0 || index >= data.chapters.length) return;
    _cancelChapterTranslation();
    final chapter = data.chapters[index];
    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _doubleAnchorOffset = null;
      _pendingOffset = chapter.startOffset;
    });
    _scheduleProgressSave();
  }

  void _goToOffset(int charOffset) {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    final location = locateAnchor(data.chapters, charOffset);
    _cancelChapterTranslation();
    setState(() {
      _chapterIndex = location.chapterIndex;
      _doubleAnchorOffset = null;
      _pendingOffset = charOffset;
    });
    _scheduleProgressSave();
  }

  void _goToNextPage() {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    final pagination = _validPagination(data.chapters);
    if (pagination == null) return;
    final step = _doubleSpread && !_translationActive ? 2 : 1;
    if (_pageIndex + step <= pagination.pageCount - 1) {
      if (!_doubleSpread) _doubleAnchorOffset = null;
      setState(() => _pageIndex += step);
      _bumpPageTurns();
      _scheduleProgressSave();
      return;
    }
    if (_chapterIndex < data.chapters.length - 1) {
      _goToChapter(_chapterIndex + 1);
    }
  }

  void _goToPreviousPage() {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    if (_validPagination(data.chapters) == null) return;
    final step = _doubleSpread && !_translationActive ? 2 : 1;
    if (_pageIndex > 0) {
      if (!_doubleSpread) _doubleAnchorOffset = null;
      setState(
        () => _pageIndex = (_pageIndex - step).clamp(0, _pageIndex - 1),
      );
      _bumpPageTurns();
      _scheduleProgressSave();
      return;
    }
    final previousIndex = _chapterIndex - 1;
    if (previousIndex < 0) return;
    final previous = data.chapters[previousIndex];
    final offset = previous.endOffset > previous.startOffset
        ? previous.endOffset - 1
        : previous.startOffset;
    setState(() {
      _chapterIndex = previousIndex;
      _doubleAnchorOffset = null;
      _pendingOffset = offset;
    });
    _scheduleProgressSave();
  }

  /// Tells the companion the page moved; it flinches for a moment.
  void _bumpPageTurns() => _pageTurns.value = _pageTurns.value + 1;

  (Color, Color) get _colors {
    return switch (_background) {
      ReaderBackground.light => (
        const Color(0xFFFCFCFD),
        const Color(0xFF3B4048),
      ),
      ReaderBackground.sepia => (
        const Color(0xFFF4ECD8),
        const Color(0xFF3B2F1E),
      ),
      ReaderBackground.dark => (
        const Color(0xFF1A1B1F),
        const Color(0xFFC6CAD1),
      ),
    };
  }

  Color get _accent => _background == ReaderBackground.dark
      ? AppTheme.darkAccent
      : AppTheme.accent;

  void _toggleRailPinned() {
    final chapters = _cachedData?.chapters ?? const <Chapter>[];
    final anchor = _currentPageStartOffset(chapters);
    _hideTimer?.cancel();
    setState(() {
      if (anchor != null) _pendingOffset = anchor;
      _railPinned = !_railPinned;
      _railVisible = !_railPinned;
    });
    _settingsRepository
        ?.set(_railPinnedKey, _railPinned.toString())
        .catchError((Object _) {});
  }

  void _showRail() {
    _hideTimer?.cancel();
    if (_railPinned || _railVisible || _suppressHotzone) return;
    setState(() => _railVisible = true);
  }

  void _scheduleHideRail() {
    if (_railPinned) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), _hideRailNow);
  }

  void _hideRailNow({bool suppressHotzone = false}) {
    _hideTimer?.cancel();
    if (suppressHotzone) _suppressHotzone = true;
    if (!mounted || !_railVisible || _railPinned) return;
    setState(() => _railVisible = false);
  }

  void _backToLibrary() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  void _openAppSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  (int, int) _pageOffsets(Chapter chapter) {
    final data = _cachedData;
    final pagination = data == null ? null : _validPagination(data.chapters);
    if (pagination == null) {
      return (chapter.startOffset, chapter.endOffset);
    }
    final page = pagination.pageAt(_pageIndex);
    final start = chapter.startOffset + page.start;
    final end = chapter.startOffset + page.end;
    return (start, end > start ? end : start + 1);
  }

  Future<void> _toggleBookmark(Chapter chapter) async {
    final repository = ref.read(annotationRepositoryProvider);
    try {
      final (pageStart, pageEnd) = _pageOffsets(chapter);
      final existing = (await repository.getForBook(
        widget.bookId,
        type: AnnotationType.bookmark,
      )).where(
        (bookmark) =>
            bookmark.chapterId == chapter.id &&
            bookmark.anchorStart >= pageStart &&
            bookmark.anchorStart < pageEnd,
      ).toList();

      if (existing.isNotEmpty) {
        for (final bookmark in existing) {
          await repository.delete(bookmark.id);
        }
        _refreshBookmarks();
        _showSnackBar('已取消书签');
        return;
      }

      final now = DateTime.now();
      await repository.upsert(
        Annotation(
          id: const Uuid().v4(),
          bookId: widget.bookId,
          chapterId: chapter.id,
          type: AnnotationType.bookmark,
          anchorStart: pageStart,
          createdAt: now,
          updatedAt: now,
        ),
      );
      _refreshBookmarks();
      _showSnackBar('已添加书签');
    } catch (_) {
      _showSnackBar('书签操作失败，请重试');
    }
  }

  Future<void> _toggleComicBookmark(int page) async {
    final repository = ref.read(annotationRepositoryProvider);
    try {
      final existing = (await repository.getForBook(
        widget.bookId,
        type: AnnotationType.bookmark,
      )).where((bookmark) => bookmark.anchorStart == page).toList();

      if (existing.isNotEmpty) {
        for (final bookmark in existing) {
          await repository.delete(bookmark.id);
        }
        _refreshBookmarks();
        _showSnackBar('已取消书签');
        return;
      }

      final now = DateTime.now();
      await repository.upsert(
        Annotation(
          id: const Uuid().v4(),
          bookId: widget.bookId,
          type: AnnotationType.bookmark,
          anchorStart: page,
          createdAt: now,
          updatedAt: now,
        ),
      );
      _refreshBookmarks();
      _showSnackBar('已添加书签');
    } catch (_) {
      _showSnackBar('书签操作失败，请重试');
    }
  }

  Future<void> _deleteBookmark(Annotation bookmark) async {
    try {
      await ref.read(annotationRepositoryProvider).delete(bookmark.id);
      _refreshBookmarks();
      _showSnackBar('已取消书签');
    } catch (_) {
      _showSnackBar('删除书签失败，请重试');
    }
  }

  void _refreshBookmarks() {
    if (!mounted) return;
    ref.invalidate(bookmarkListProvider(widget.bookId));
  }

  void _refreshAnnotations() {
    if (!mounted) return;
    ref.invalidate(readerAnnotationListProvider(widget.bookId));
  }

  Future<void> _highlightSelection(
    Chapter chapter,
    PageSlice page,
    TextSelection selection,
    String text,
  ) async {
    final color = await _pickHighlightColor();
    if (color == null || !mounted) return;
    await _saveSelectionAnnotation(
      chapter,
      page,
      selection,
      text,
      (anchorStart, anchorEnd, selectedText) => ref
          .read(annotationServiceProvider)
          .addHighlight(
            bookId: widget.bookId,
            chapterId: chapter.id,
            anchorStart: anchorStart,
            anchorEnd: anchorEnd,
            selectedText: selectedText,
            color: color,
          ),
      successMessage: '已添加高亮',
    );
  }

  Future<void> _addNote(
    Chapter chapter,
    PageSlice page,
    TextSelection selection,
    String text,
  ) async {
    final selectedText = _selectedText(selection, text);
    final noteText = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(selectedText: selectedText),
    );
    if (noteText == null || !mounted) return;
    await _saveSelectionAnnotation(
      chapter,
      page,
      selection,
      text,
      (anchorStart, anchorEnd, text) => ref
          .read(annotationServiceProvider)
          .addNote(
            bookId: widget.bookId,
            chapterId: chapter.id,
            anchorStart: anchorStart,
            anchorEnd: anchorEnd,
            selectedText: text,
            noteText: noteText,
          ),
      successMessage: '已添加笔记',
    );
  }

  Future<void> _saveSelectionAnnotation(
    Chapter chapter,
    PageSlice page,
    TextSelection selection,
    String text,
    Future<void> Function(int anchorStart, int anchorEnd, String selectedText)
    save, {
    required String successMessage,
  }) async {
    if (!selection.isValid || selection.isCollapsed) return;
    try {
      await save(
        absoluteOffsetForPageSelection(chapter, page, selection.start),
        absoluteOffsetForPageSelection(chapter, page, selection.end),
        _selectedText(selection, text),
      );
      _refreshAnnotations();
      _showSnackBar(successMessage);
    } catch (_) {
      _showSnackBar('标注失败，请重试');
    }
  }

  String _selectedText(TextSelection selection, String text) {
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    return text.substring(start, end);
  }

  List<InlineSpan> _pageSpans({
    required String text,
    required PageSlice page,
    required ChapterPagination pagination,
    required Chapter chapter,
    required List<Annotation> annotations,
    required TextStyle baseStyle,
  }) {
    final spans = <InlineSpan>[];
    final heading = pagination.headingText;
    final headingEnd = heading?.length ?? 0;
    if (heading == null || page.start >= headingEnd) {
      spans.addAll(
        buildAnnotationSpans(
          text: text.substring(page.start, page.end),
          chapterStart: chapter.startOffset + page.start,
          annotations: annotations,
          baseStyle: baseStyle,
        ),
      );
      return spans;
    }
    final headingPartEnd = headingEnd < page.end ? headingEnd : page.end;
    if (headingPartEnd > page.start) {
      spans.add(
        TextSpan(
          text: text.substring(page.start, headingPartEnd),
          style: headingTextStyle(baseStyle, chapter.level),
        ),
      );
    }
    if (headingPartEnd < page.end) {
      spans.addAll(
        buildAnnotationSpans(
          text: text.substring(headingPartEnd, page.end),
          chapterStart: chapter.startOffset + headingPartEnd,
          annotations: annotations,
          baseStyle: baseStyle,
        ),
      );
    }
    return spans;
  }

  String _illustrationSignature(List<BookIllustration> images) => images
      .map(
        (image) =>
            '${image.path}|${image.offset}|${image.width}x${image.height}',
      )
      .join(',');

  Widget _illustrationBlock(PageIllustration image) {
    final index = _illustrationSeq++;
    final key = GlobalKey();
    _illustrationTargets = [
      ..._illustrationTargets,
      (key: key, path: image.path),
    ];
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: image.gap),
      child: Center(
        child: GestureDetector(
          key: ValueKey('reader-illustration-$index'),
          onTap: () => openIllustrationViewer(context, image.path),
          child: SizedBox(
            width: image.width,
            height: image.height,
            child: Image.file(
              File(image.path),
              key: key,
              fit: BoxFit.contain,
              cacheWidth: (image.width * ratio).round(),
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  bool _openIllustrationAt(Offset globalPosition) {
    for (final target in _illustrationTargets) {
      final box = target.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      if ((box.localToGlobal(Offset.zero) & box.size).contains(globalPosition)) {
        openIllustrationViewer(context, target.path);
        return true;
      }
    }
    return false;
  }

  Widget _pageContent({
    required String text,
    required PageSlice page,
    required ChapterPagination pagination,
    required Chapter chapter,
    required List<Annotation> annotations,
    required TextStyle baseStyle,
    bool showImages = true,
  }) {
    if (!showImages || page.images.isEmpty) {
      final content = text.substring(page.start, page.end);
      return SelectableText.rich(
        TextSpan(
          children: _pageSpans(
            text: text,
            page: page,
            pagination: pagination,
            chapter: chapter,
            annotations: annotations,
            baseStyle: baseStyle,
          ),
        ),
        scrollBehavior: ScrollConfiguration.of(
          context,
        ).copyWith(scrollbars: false),
        scrollPhysics: const NeverScrollableScrollPhysics(),
        contextMenuBuilder: (context, state) =>
            _selectionToolbar(state, page, content, chapter),
      );
    }

    final images = [...page.images]
      ..sort((a, b) => a.offset.compareTo(b.offset));
    final blocks = <Widget>[];
    var nextImage = 0;
    void addImagesThrough(int offset) {
      while (nextImage < images.length && images[nextImage].offset <= offset) {
        blocks.add(_illustrationBlock(images[nextImage++]));
      }
    }

    for (final fragment in pageTextFragments(page)) {
      addImagesThrough(fragment.start);
      // A fragment's trailing newline only separates lines that the paginator
      // already counted; rendering it inside its own SelectableText would add
      // a blank line the paginator never budgeted for and overflow the page.
      var displayEnd = fragment.end;
      while (displayEnd > fragment.start &&
          (text[displayEnd - 1] == '\n' || text[displayEnd - 1] == '\r')) {
        displayEnd--;
      }
      final display = PageSlice(start: fragment.start, end: displayEnd);
      blocks.add(
        KeyedSubtree(
          key: ValueKey('${chapter.id}-${page.start}-frag-${fragment.start}'),
          child: SelectableText.rich(
            TextSpan(
              children: _pageSpans(
                text: text,
                page: display,
                pagination: pagination,
                chapter: chapter,
                annotations: annotations,
                baseStyle: baseStyle,
              ),
            ),
            scrollBehavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            scrollPhysics: const NeverScrollableScrollPhysics(),
            contextMenuBuilder: (context, state) => _selectionToolbar(
              state,
              display,
              text.substring(fragment.start, displayEnd),
              chapter,
            ),
          ),
        ),
      );
    }
    addImagesThrough(page.end);
    return ClipRect(
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: blocks,
        ),
      ),
    );
  }

  List<InlineSpan> _translationSpans({
    required PageSlice page,
    required ChapterPagination pagination,
    required Chapter chapter,
    required TextStyle baseStyle,
  }) {
    final spans = <InlineSpan>[];
    for (final block in blocksForRange(
      _translationBlocks,
      page.start,
      page.end,
    )) {
      if (block.translation.isEmpty) continue;
      final heading = block.start == 0 && pagination.headingText != null;
      if (spans.isNotEmpty) {
        spans.add(TextSpan(text: '\n\n', style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: block.translation,
          style: heading
              ? headingTextStyle(baseStyle, chapter.level)
              : baseStyle,
        ),
      );
    }
    return spans;
  }

  Widget _translatedPane({
    required PageSlice page,
    required ChapterPagination pagination,
    required Chapter chapter,
    required TextStyle baseStyle,
  }) {
    final spans = _translationSpans(
      page: page,
      pagination: pagination,
      chapter: chapter,
      baseStyle: baseStyle,
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kPaneHorizontalPadding,
        ),
        child: ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            child: KeyedSubtree(
              key: ValueKey('${chapter.id}-${page.start}-translation'),
              child: SelectableText.rich(
                TextSpan(children: spans),
                scrollBehavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                scrollPhysics: const NeverScrollableScrollPhysics(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _translationProgressChip() {
    final (background, foreground) = _colors;
    return Container(
      key: const Key('reader-translation-progress'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: _translationTotal == 0
                  ? null
                  : _translationDone / _translationTotal,
              color: _accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '正在翻译 $_translationDone / $_translationTotal',
            style: TextStyle(color: foreground, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _openAnnotations(List<Chapter> chapters) async {
    final anchor = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) =>
            AnnotationsPage(bookId: widget.bookId, chapters: chapters),
      ),
    );
    if (anchor == null || !mounted) return;
    _refreshAnnotations();
    _goToOffset(anchor);
  }

  Future<void> _toggleCompanion() async {
    if (_companionOpen) {
      _closeCompanion();
      return;
    }
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    final index = _chapterIndex.clamp(0, data.chapters.length - 1);
    final chapter = data.chapters[index];
    final text = await ref.read(
      chapterContentProvider((bookId: widget.bookId, index: index)).future,
    );
    if (!mounted) return;
    final offset =
        (_currentProgress()?.anchor.charOffset ?? chapter.startOffset) -
        chapter.startOffset;
    final pageInfo = _companionPageInfo(index, data.chapters, text);

    // A side column narrows the reading area, so keep the reader on the same
    // passage across the re-pagination. Phones keep the bottom sheet.
    if (MediaQuery.sizeOf(context).width < _companionDockMinWidth) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => CompanionPanel(
          bookId: widget.bookId,
          chapterIndex: index,
          chapterTitle: chapter.title,
          chapterText: text,
          chapterCharOffset: offset < 0 ? 0 : offset,
          chapterPage: pageInfo.page,
          chapterPageEnd: pageInfo.pageEnd,
          chapterPageCount: pageInfo.pageCount,
          bookPage: pageInfo.bookPage,
          bookPageTotal: pageInfo.bookPageTotal,
          pageStartOffset: pageInfo.startOffset,
          pageEndOffset: pageInfo.endOffset,
          currentPageText: pageInfo.text,
          bookTitle: data.book?.title ?? '',
          author: data.book?.author ?? '',
          onGoToChapter: (index) {
            Navigator.of(context).pop();
            _goToChapter(index);
          },
        ),
      );
      return;
    }

    final anchor = _currentPageStartOffset(data.chapters);
    ++_companionLoadToken;
    setState(() {
      if (anchor != null) _pendingOffset = anchor;
      _companionOpen = true;
      _companionChapterIndex = index;
      _companionLoadingIndex = null;
      _companionChapterText = text;
      _companionCharOffset = offset < 0 ? 0 : offset;
    });
  }

  void _closeCompanion() {
    ++_companionLoadToken;
    final anchor = _currentPageStartOffset(_cachedData?.chapters ?? const []);
    setState(() {
      if (anchor != null) _pendingOffset = anchor;
      _companionOpen = false;
      _companionLoadingIndex = null;
    });
  }

  void _ensureCompanionChapter(int index) {
    if (_companionChapterIndex == index || _companionLoadingIndex == index) {
      return;
    }
    unawaited(_loadCompanionChapter(index));
  }

  Future<void> _loadCompanionChapter(int index) async {
    final data = _cachedData;
    if (data == null || index < 0 || index >= data.chapters.length) return;
    _companionLoadingIndex = index;
    final token = ++_companionLoadToken;
    try {
      final text = await ref.read(
        chapterContentProvider((bookId: widget.bookId, index: index)).future,
      );
      if (!mounted || token != _companionLoadToken || !_companionOpen) return;
      setState(() {
        _companionChapterIndex = index;
        _companionChapterText = text;
        _companionCharOffset = 0;
      });
    } finally {
      if (mounted && _companionLoadingIndex == index) {
        _companionLoadingIndex = null;
      }
    }
  }

  ({
    int? page,
    int? pageEnd,
    int? pageCount,
    int? bookPage,
    int? bookPageTotal,
    int? startOffset,
    int? endOffset,
    String text,
  }) _companionPageInfo(
    int chapterIndex,
    List<Chapter> chapters,
    String chapterText,
  ) {
    const empty = (
      page: null,
      pageEnd: null,
      pageCount: null,
      bookPage: null,
      bookPageTotal: null,
      startOffset: null,
      endOffset: null,
      text: '',
    );
    final pagination = _pagination;
    if (pagination == null ||
        chapterIndex < 0 ||
        chapterIndex >= chapters.length ||
        _paginationChapterId != chapters[chapterIndex].id ||
        pagination.pageCount == 0) {
      return empty;
    }
    final startIndex = _pageIndex.clamp(0, pagination.pageCount - 1);
    final spreadEnd = _doubleSpread && !_translationActive ? _pageEndIndex : null;
    final endIndex = spreadEnd == null
        ? startIndex
        : spreadEnd.clamp(startIndex, pagination.pageCount - 1);
    final start = pagination.pageAt(startIndex).start;
    final end = pagination.pageAt(endIndex).end;
    final pageText = start >= 0 && end > start && end <= chapterText.length
        ? chapterText.substring(start, end).trim()
        : '';
    final counts = _bookPageCountsSignature != null &&
            _bookPageCountsSignature == _bookPageSignature &&
            _bookPageCounts != null &&
            _bookPageCounts!.length == chapters.length
        ? _bookPageCounts
        : null;
    int? bookPage;
    int? bookPageTotal;
    if (counts != null) {
      bookPageTotal = counts.fold<int>(0, (sum, count) => sum + count);
      bookPage = bookPageAt(
        chapterPageCounts: counts,
        chapterIndex: chapterIndex,
        pageIndex: startIndex,
      );
    }
    return (
      page: startIndex + 1,
      pageEnd: endIndex > startIndex ? endIndex + 1 : null,
      pageCount: pagination.pageCount,
      bookPage: bookPage,
      bookPageTotal: bookPageTotal,
      startOffset: start >= 0 ? start : null,
      endOffset: start >= 0 && end > start ? end : null,
      text: pageText,
    );
  }

  Widget? _buildCompanionPanel(
    ReaderData data,
    List<Chapter> chapters,
    int currentIndex,
    Chapter currentChapter,
  ) {
    if (!_companionOpen) return null;
    final loadedIndex = _companionChapterIndex;
    if (loadedIndex == null) return null;
    final panelIndex = loadedIndex.clamp(0, chapters.length - 1);
    final panelChapter = chapters[panelIndex];
    final pagination = _pagination;
    final offset =
        panelIndex == currentIndex &&
            pagination != null &&
            pagination.pageCount > 0 &&
            _paginationChapterId == currentChapter.id
        ? pagination.pageAt(_pageIndex.clamp(0, pagination.pageCount - 1)).start
        : _companionCharOffset;
    final pageInfo =
        _companionPageInfo(panelIndex, chapters, _companionChapterText);
    return SizedBox(
      width: _companionPanelWidth,
      child: CompanionPanel(
        bookId: widget.bookId,
        chapterIndex: panelIndex,
        chapterTitle: panelChapter.title,
        chapterText: _companionChapterText,
        chapterCharOffset: offset,
        chapterPage: pageInfo.page,
        chapterPageEnd: pageInfo.pageEnd,
        chapterPageCount: pageInfo.pageCount,
        bookPage: pageInfo.bookPage,
        bookPageTotal: pageInfo.bookPageTotal,
        pageStartOffset: pageInfo.startOffset,
        pageEndOffset: pageInfo.endOffset,
        currentPageText: pageInfo.text,
        bookTitle: data.book?.title ?? '',
        author: data.book?.author ?? '',
        docked: true,
        onClose: _closeCompanion,
        onGoToChapter: _goToChapter,
      ),
    );
  }

  Future<void> _openIllustration() async {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    final index = _chapterIndex.clamp(0, data.chapters.length - 1);
    final chapter = data.chapters[index];
    final source = await showIllustrationSourceSheet(context);
    if (source == null || !mounted) return;
    final chapterText = await ref.read(
      chapterContentProvider((bookId: widget.bookId, index: index)).future,
    );
    if (!mounted) return;
    final pagination = _paginationChapterId == chapter.id ? _pagination : null;
    final text = illustrationTextForSource(
      source: source,
      chapterText: chapterText,
      pagination: pagination,
      startPage: _pageIndex,
      endPage: _pageEndIndex ?? _pageIndex,
    );
    await _openIllustrationComposer(
      text,
      [data.book?.title ?? '', chapter.title, source.label]
          .where((part) => part.trim().isNotEmpty)
          .join(' · '),
    );
  }

  Future<void> _openIllustrationComposer(String text, String label) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IllustrationComposerPage(
          initialText: text,
          contextLabel: label,
        ),
      ),
    );
  }

  void _openIllustrationJob(IllustrationJob job) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IllustrationComposerPage(
          jobId: job.id,
          initialText: job.text,
          contextLabel: job.label,
        ),
      ),
    );
  }

  Widget _illustrationJobPill(IllustrationJob job) {
    final running = job.isRunning;
    final done = job.status == IllustrationJobStatus.done;
    final label = running
        ? '插画生成中 · ${job.stage?.label ?? '准备中…'}'
        : done
            ? '插画已生成'
            : '插画生成失败';
    return Material(
      key: const Key('reader-illustration-job'),
      color: _colors.$1,
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: const Key('reader-illustration-job-open'),
        borderRadius: BorderRadius.circular(24),
        onTap: () => _openIllustrationJob(job),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (running)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accent,
                  ),
                )
              else
                Icon(
                  done ? Icons.image_outlined : Icons.error_outline,
                  size: 18,
                  color: done ? _accent : Colors.redAccent,
                ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: _colors.$2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                running ? '查看进度' : '查看',
                style: TextStyle(fontSize: 12, color: _accent),
              ),
              if (running)
                IconButton(
                  key: const Key('reader-illustration-job-stop'),
                  tooltip: '停止生成',
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: () =>
                      ref.read(illustrationJobProvider.notifier).cancel(),
                  icon: Icon(Icons.stop_circle_outlined, color: _colors.$2),
                )
              else
                IconButton(
                  key: const Key('reader-illustration-job-dismiss'),
                  tooltip: '关闭提示',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: () =>
                      ref.read(illustrationJobProvider.notifier).dismiss(),
                  icon: Icon(Icons.close, color: _colors.$2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pickHighlightColor() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('选择高亮颜色')),
              for (final entry in highlightColorLabels.entries)
                ListTile(
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: highlightColorFor(entry.key),
                  ),
                  title: Text(entry.value),
                  onTap: () => Navigator.of(sheetContext).pop(entry.key),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openTranslation(String title, String sourceText) async {
    if (sourceText.trim().isEmpty) {
      _showSnackBar('没有可翻译的内容');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => TranslationDialog(
        title: title,
        sourceText: sourceText,
        service: ref.read(translationServiceProvider),
        cache: ref.read(translationCacheProvider),
      ),
    );
  }

  Future<void> _toggleChapterTranslation(Chapter chapter) async {
    if (_translationVisible && _translationChapterId == chapter.id) {
      setState(() {
        _translationVisible = false;
        _translationActive = false;
      });
      return;
    }
    final cached = _translationCache[chapter.id];
    if (cached != null && cached.isNotEmpty) {
      _showTranslation(cached, chapter);
      return;
    }
    await _startChapterTranslation(chapter);
  }

  void _showTranslation(List<TranslationBlock> blocks, Chapter chapter) {
    setState(() {
      _translationBlocks = blocks;
      _translationChapterId = chapter.id;
      _translationVisible = true;
    });
  }

  Future<void> _startChapterTranslation(Chapter chapter) async {
    final text = _chapterText;
    if (_chapterTextChapterId != chapter.id) {
      _showSnackBar('章节还在加载，请稍后再试');
      return;
    }
    if (text.trim().isEmpty) {
      _showSnackBar('本章暂时没有可翻译的内容');
      return;
    }
    if (isPredominantlyChinese(text)) {
      _showSnackBar('原文已是中文，无需翻译');
      return;
    }
    final blocks = splitTranslationBlocks(text);
    if (blocks.isEmpty) {
      _showSnackBar('本章暂时没有可翻译的内容');
      return;
    }

    final token = ++_translationToken;
    setState(() {
      _translationBusy = true;
      _translationVisible = false;
      _translationChapterId = chapter.id;
      _translationBlocks = const [];
      _translationDone = 0;
      _translationTotal = blocks.length;
    });

    final service = ref.read(translationServiceProvider);
    final translated = <TranslationBlock>[];
    try {
      for (final block in blocks) {
        final buffer = StringBuffer();
        await for (final chunk in service.translate(
          block.source,
          targetLang: 'zh-CN',
        )) {
          if (!mounted || token != _translationToken) return;
          buffer.write(chunk);
        }
        if (!mounted || token != _translationToken) return;
        translated.add(block.withTranslation(buffer.toString().trim()));
        setState(() => _translationDone = translated.length);
      }
    } catch (error) {
      if (!mounted || token != _translationToken) return;
      setState(() {
        _translationBusy = false;
        _translationChapterId = null;
        _translationBlocks = const [];
      });
      _showSnackBar(_translationErrorMessage(error));
      return;
    }

    if (!mounted || token != _translationToken) return;
    final withText = translated
        .where((block) => block.translation.isNotEmpty)
        .toList();
    if (withText.isEmpty) {
      setState(() {
        _translationBusy = false;
        _translationChapterId = null;
        _translationBlocks = const [];
      });
      _showSnackBar('翻译服务没有返回译文，请稍后重试');
      return;
    }

    _translationCache[chapter.id] = withText;
    final stillHere = _currentChapterId() == chapter.id;
    setState(() {
      _translationBusy = false;
      _translationChapterId = chapter.id;
      _translationBlocks = withText;
      _translationVisible = stillHere;
    });
  }

  String? _currentChapterId() {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return null;
    final index = _chapterIndex.clamp(0, data.chapters.length - 1);
    return data.chapters[index].id;
  }

  String _translationErrorMessage(Object error) {
    if (error is TranslationException) return error.message;
    if (error is AssistantNotConfiguredException) return '未配置 AI 服务';
    return '翻译失败，请稍后重试';
  }

  void _cancelChapterTranslation() {
    _translationToken++;
    if (!_translationBusy &&
        !_translationVisible &&
        _translationBlocks.isEmpty) {
      return;
    }
    setState(() {
      _translationBusy = false;
      _translationVisible = false;
      _translationActive = false;
      _translationChapterId = null;
      _translationBlocks = const [];
    });
  }

  void _illustrateSelection(Chapter chapter, TextSelection selection, String text) {
    final selected = _selectedText(selection, text).trim();
    if (selected.isEmpty) return;
    _openIllustrationComposer(
      selected,
      [_cachedData?.book?.title ?? '', chapter.title, '选中文字']
          .where((part) => part.trim().isNotEmpty)
          .join(' · '),
    );
  }

  void _translateSelection(TextSelection selection, String text) {
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    if (start >= end) return;
    _openTranslation('翻译选中内容', text.substring(start, end));
  }

  void _translateFromSelection(TextSelection selection, String text) {
    final start = selection.start.clamp(0, text.length);
    if (start >= text.length) return;
    _openTranslation('从此处开始翻译', text.substring(start));
  }

  Widget _selectionToolbar(
    EditableTextState editableTextState,
    PageSlice page,
    String text,
    Chapter chapter,
  ) {
    final selection = editableTextState.textEditingValue.selection;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: [
        if (selection.isValid && !selection.isCollapsed) ...[
          ContextMenuButtonItem(
            label: '高亮',
            onPressed: () {
              editableTextState.hideToolbar();
              _highlightSelection(chapter, page, selection, text);
            },
          ),
          ContextMenuButtonItem(
            label: '笔记',
            onPressed: () {
              editableTextState.hideToolbar();
              _addNote(chapter, page, selection, text);
            },
          ),
          ContextMenuButtonItem(
            label: '生成插画',
            onPressed: () {
              editableTextState.hideToolbar();
              _illustrateSelection(chapter, selection, text);
            },
          ),
          ContextMenuButtonItem(
            label: '翻译',
            onPressed: () {
              editableTextState.hideToolbar();
              _translateSelection(selection, text);
            },
          ),
          ContextMenuButtonItem(
            label: '从此段翻译',
            onPressed: () {
              editableTextState.hideToolbar();
              _translateFromSelection(selection, text);
            },
          ),
        ],
        ...editableTextState.contextMenuButtonItems,
      ],
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return ReaderSettingsSheet(
              fontSize: _fontSize,
              lineHeight: _lineHeight,
              background: _background,
              spread: _spread,
              onChanged: (fontSize, lineHeight, background, spread) {
                final chapters = _cachedData?.chapters ?? const <Chapter>[];
                final anchor = _currentPageStartOffset(chapters);
                setState(() {
                  if (anchor != null) _pendingOffset = anchor;
                  _doubleAnchorOffset = null;
                  _fontSize = fontSize;
                  _lineHeight = lineHeight;
                  _background = background;
                  _spread = spread;
                });
                setSheet(() {});
                _scheduleSaveReadingSettings();
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(readerDataProvider(widget.bookId));
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: data.when(
      loading: () => _scaffold(
        title: '阅读',
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _scaffold(
        title: '阅读',
        body: Center(child: Text('加载失败：$error')),
      ),
      data: (readerData) {
        _cachedData = readerData;
        _progressRepository ??= ref.read(progressRepositoryProvider);
        _scheduleRestore(readerData);
        final title = readerData.book?.title ?? '阅读';
        if (readerData.book?.comic ?? false) {
          return _buildComic(readerData, title);
        }
        if (readerData.chapters.isEmpty) {
          return _scaffold(
            title: title,
            body: const Center(child: Text('这本书暂时没有可显示的章节')),
          );
        }

        final chapters = readerData.chapters;
        final index = _chapterIndex < 0
            ? 0
            : (_chapterIndex >= chapters.length
                  ? chapters.length - 1
                  : _chapterIndex);
        final content = ref.watch(
          chapterContentProvider((bookId: widget.bookId, index: index)),
        );
        final bookmarks =
            ref.watch(bookmarkListProvider(widget.bookId)).value ??
            const <Annotation>[];
        final annotations =
            ref.watch(readerAnnotationListProvider(widget.bookId)).value ??
            const <Annotation>[];
        final currentChapter = chapters[index];
        final illustrations = readerData.illustrations;
        final chapterImages = [
          for (final image in illustrations)
            if (image.chapterIndex == index) image,
        ];
        if (_companionOpen && _companionChapterIndex != index) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _companionOpen) _ensureCompanionChapter(index);
          });
        }
        final (bookmarkPageStart, bookmarkPageEnd) = _pageOffsets(
          currentChapter,
        );
        final pageBookmarked = bookmarks.any(
          (bookmark) =>
              bookmark.chapterId == currentChapter.id &&
              bookmark.anchorStart >= bookmarkPageStart &&
              bookmark.anchorStart < bookmarkPageEnd,
        );
        final chapterAnnotations = annotations
            .where((annotation) => annotation.chapterId == currentChapter.id)
            .toList();
        final translationShown =
            _translationVisible &&
            _translationChapterId == currentChapter.id &&
            _translationBlocks.isNotEmpty;
        _translationActive = translationShown;

        final contentBody = content.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('章节加载失败：$error')),
          data: (text) {
            _chapterText = text;
            _chapterTextChapterId = currentChapter.id;
            final baseStyle = TextStyle(
              fontSize: _fontSize,
              height: _lineHeight,
              color: _colors.$2,
              fontFamily: 'Source Han Serif SC',
              fontFamilyFallback: const [
                'Noto Serif CJK SC',
                'SimSun',
                'Georgia',
              ],
            );
            final textScaler = MediaQuery.textScalerOf(context);
            return LayoutBuilder(
              builder: (context, constraints) {
                // SelectableText merges the ambient DefaultTextStyle into the
                // spans it renders, so paginate with that same merged style or
                // the measured line breaks drift from the painted ones.
                final effectiveBaseStyle = DefaultTextStyle.of(
                  context,
                ).style.merge(baseStyle);
                final doubleSpread = spreadApplies(
                  _spread,
                  constraints.maxWidth,
                );
                final textWidth = doubleSpread
                    ? spreadTextWidth(
                        constraints.maxWidth,
                      ).clamp(1.0, double.infinity)
                    : (constraints.maxWidth.clamp(0.0, 720.0) - 40).clamp(
                        1.0,
                        720.0,
                      );
                final textHeight = (constraints.maxHeight - 48).clamp(
                  1.0,
                  double.infinity,
                );
                final key =
                    '${currentChapter.id}|$_fontSize|$_lineHeight|'
                    '${textScaler.scale(1).toStringAsFixed(3)}|'
                    '${textWidth.round()}|${textHeight.round()}|'
                    '${text.length}|${doubleSpread ? 'double' : 'single'}|'
                    '${_illustrationSignature(chapterImages)}';
                ChapterPagination pagination;
                if (_paginationKey == key &&
                    _paginationChapterId == currentChapter.id &&
                    _pagination != null) {
                  pagination = _pagination!;
                } else {
                  pagination = paginateChapter(
                    text: text,
                    title: currentChapter.title,
                    level: currentChapter.level,
                    baseStyle: effectiveBaseStyle,
                    width: textWidth,
                    height: textHeight,
                    textScaler: textScaler,
                    illustrations: chapterImages,
                  );
                  _pagination = pagination;
                  _paginationKey = key;
                  _paginationChapterId = currentChapter.id;
                }
                final bookSignature =
                    '$_fontSize|$_lineHeight|'
                    '${textScaler.scale(1).toStringAsFixed(3)}|'
                    '${textWidth.round()}|${textHeight.round()}|'
                    '${chapters.length}|'
                    '${doubleSpread ? 'double' : 'single'}|'
                    '${_illustrationSignature(illustrations)}';
                if (bookSignature != _bookPageSignature) {
                  _bookPageSignature = bookSignature;
                  final layout = PageLayout(
                    baseStyle: effectiveBaseStyle,
                    width: textWidth,
                    height: textHeight,
                    textScaler: textScaler,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _bookPageSignature != bookSignature) return;
                    _startBookPageCount(
                      layout,
                      chapters,
                      bookSignature,
                      illustrations,
                    );
                  });
                }
                final pending = _pendingOffset;
                var pageIndex = pending != null
                    ? pagination.pageIndexForOffset(
                        pending - currentChapter.startOffset,
                      )
                    : _pageIndex;
                pageIndex = pageIndex.clamp(0, pagination.pageCount - 1);
                if (doubleSpread && !translationShown) {
                  pageIndex = spreadPageIndex(pageIndex);
                }
                final page = pagination.pageAt(pageIndex);
                if (doubleSpread && !translationShown) {
                  _doubleAnchorOffset = currentChapter.startOffset + page.start;
                }
                _pageIndex = pageIndex;
                final nextPageEndIndex = doubleSpread && !translationShown
                    ? spreadLastPageIndex(pageIndex, pagination.pageCount)
                    : null;
                final endIndexChanged = _pageEndIndex != nextPageEndIndex;
                _pageEndIndex = nextPageEndIndex;
                _pendingOffset = null;
                _restored = true;
                final spreadChanged = doubleSpread != _doubleSpread;
                _doubleSpread = doubleSpread;
                if (pending != null || spreadChanged || endIndexChanged) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }

                Widget pagePane(int? paneIndex) {
                  if (paneIndex == null || paneIndex >= pagination.pageCount) {
                    return const Expanded(
                      child: SizedBox.expand(
                        key: Key('reader-spread-blank'),
                      ),
                    );
                  }
                  final panePage = pagination.pageAt(paneIndex);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kPaneHorizontalPadding,
                      ),
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: KeyedSubtree(
                            key: ValueKey(
                              '${currentChapter.id}-$paneIndex-$_paginationKey',
                            ),
                            child: _pageContent(
                              text: text,
                              page: panePage,
                              pagination: pagination,
                              chapter: currentChapter,
                              annotations: chapterAnnotations,
                              baseStyle: baseStyle,
                              showImages: !translationShown,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                _illustrationTargets = const [];
                _illustrationSeq = 0;
                _pageText = text.substring(page.start, page.end);
                final Widget pageBody;
                if (doubleSpread) {
                  final contentWidth = constraints.maxWidth.clamp(
                    0.0,
                    kSpreadContentMaxWidth,
                  );
                  pageBody = Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 32),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pagePane(pageIndex),
                            VerticalDivider(
                              width: kSpreadGutterWidth,
                              thickness: 1,
                              color: _colors.$2.withValues(alpha: 0.12),
                            ),
                            if (translationShown)
                              _translatedPane(
                                page: page,
                                pagination: pagination,
                                chapter: currentChapter,
                                baseStyle: baseStyle,
                              )
                            else
                              pagePane(pageIndex + 1),
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  final pageChild = translationShown
                      ? SelectableText.rich(
                          TextSpan(
                            children: _translationSpans(
                              page: page,
                              pagination: pagination,
                              chapter: currentChapter,
                              baseStyle: baseStyle,
                            ),
                          ),
                          scrollBehavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          scrollPhysics: const NeverScrollableScrollPhysics(),
                        )
                      : _pageContent(
                          text: text,
                          page: page,
                          pagination: pagination,
                          chapter: currentChapter,
                          annotations: chapterAnnotations,
                          baseStyle: baseStyle,
                        );
                  pageBody = Center(
                    child: SizedBox(
                      width: constraints.maxWidth.clamp(0.0, 720.0),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        child: SizedBox(
                          width: textWidth,
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: KeyedSubtree(
                                key: ValueKey(
                                  '${currentChapter.id}-$_pageIndex-$_paginationKey'
                                  '-${translationShown ? 'translated' : 'source'}',
                                ),
                                child: pageChild,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Stack(
                  key: const Key('reader-page'),
                  fit: StackFit.expand,
                  children: [
                    pageBody,
                    if (_translationBusy &&
                        _translationChapterId == currentChapter.id)
                      Positioned(
                        top: 12,
                        right: 24,
                        child: _translationProgressChip(),
                      ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: constraints.maxWidth * 0.3,
                      child: GestureDetector(
                        key: const Key('reader-prev-zone'),
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) {
                          if (_openIllustrationAt(details.globalPosition)) {
                            return;
                          }
                          _goToPreviousPage();
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: constraints.maxWidth * 0.3,
                      child: GestureDetector(
                        key: const Key('reader-next-zone'),
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) {
                          if (_openIllustrationAt(details.globalPosition)) {
                            return;
                          }
                          _goToNextPage();
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );

        final companionPanel = _buildCompanionPanel(
          readerData,
          chapters,
          index,
          currentChapter,
        );
        final body = _decorateBody(
          contentBody,
          companion: _CompanionWiring(
            greetingLoader: () =>
                _companionGreeting(currentChapter, _pageText),
            onSpeak: () => _speakLine(currentChapter, _pageText),
            onSpokenLine: _readBubbleAloud,
            onChatSend: (text) => _chatController.ask(
              currentChapter.id,
              _chatContext(currentChapter),
              text,
            ),
            chatChapterId: currentChapter.id,
            chatTitle: '陪读 · ${currentChapter.title}',
          ),
        );
        final readerBody = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _hideRailNow(suppressHotzone: true),
            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                _goToPreviousPage,
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                _goToNextPage,
            const SingleActivator(LogicalKeyboardKey.pageUp):
                _goToPreviousPage,
            const SingleActivator(LogicalKeyboardKey.pageDown):
                _goToNextPage,
          },
          child: Focus(autofocus: true, child: body),
        );
        final job = ref.watch(illustrationJobProvider);
        final readerBodyWithJob = job == null
            ? readerBody
            : Stack(
                fit: StackFit.expand,
                children: [
                  readerBody,
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: _illustrationJobPill(job),
                  ),
                ],
              );
        final scaffoldBody = companionPanel == null
            ? readerBodyWithJob
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: readerBodyWithJob),
                  companionPanel,
                ],
              );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _colors.$1,
          appBar: ReaderTopBar(
            title: '$title · ${currentChapter.title}',
            background: _colors.$1,
            foreground: _colors.$2,
            pinned: _railPinned,
            onTogglePinned: _toggleRailPinned,
            bookmarked: pageBookmarked,
            onToggleBookmark: () => _toggleBookmark(currentChapter),
            onOpenAnnotations: () => _openAnnotations(chapters),
            onTranslate: () => _toggleChapterTranslation(currentChapter),
            translationActive:
                _translationVisible &&
                _translationChapterId == currentChapter.id,
            translationBusy:
                _translationBusy &&
                _translationChapterId == currentChapter.id,
            onOpenToc: () => _scaffoldKey.currentState?.openEndDrawer(),
            onOpenCompanion: _toggleCompanion,
            onOpenReaderSettings: _openSettings,
          ),
          endDrawer: TocDrawer(
            chapters: chapters,
            currentIndex: index,
            currentChapterId: currentChapter.id,
            bookmarks: bookmarks,
            onSelect: (selected) => _goToChapter(selected),
            onSelectBookmark: _goToOffset,
            onDeleteBookmark: _deleteBookmark,
          ),
          body: scaffoldBody,
          bottomNavigationBar: _navigationBar(index, chapters),
        );
      },
      ),
    );
  }

  /// Greeting lines already requested, keyed by chapter id.
  final Map<String, Future<String?>> _greetings = {};

  /// One thread per chapter; closing the panel must not lose the talk.
  late final CompanionChatController _chatController;

  bool _chatOpen = false;

  void _toggleChat() => setState(() => _chatOpen = !_chatOpen);

  /// Reads a bubble line out loud in the configured voice.
  ///
  /// The pet talks, so the line is spoken even when 朗读 is off: that switch
  /// decides whether long chat replies are read on their own, not whether the
  /// pet may say what it is showing. Voice, speed and volume still come from
  /// [TtsConfig].
  void _readBubbleAloud(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    unawaited(ref.read(ttsServiceProvider).speak(trimmed, force: true));
  }

  /// A fresh line for every click; unlike the greeting it is never cached.
  Future<String?> _speakLine(Chapter chapter, String pageText) async {
    await ref.read(personaModeProvider.notifier).ensureRestored();
    final offset =
        (_currentProgress()?.anchor.charOffset ?? chapter.startOffset) -
        chapter.startOffset;
    return ref.read(companionGreeterProvider)(
      CompanionGreetingRequest(
        bookId: widget.bookId,
        chapterIndex: chapter.index,
        chapterTitle: chapter.title,
        chapterText: chapter.contentText,
        pageText: pageText,
        readerOffset: offset < 0 ? 0 : offset,
        bookTitle: _cachedData?.book?.title ?? '',
        author: _cachedData?.book?.author ?? '',
      ),
    );
  }

  ReadingContext _chatContext(Chapter chapter) => ReadingContext(
    bookTitle: _cachedData?.book?.title ?? '',
    author: _cachedData?.book?.author ?? '',
    chapterTitle: chapter.title,
    chapterText: chapter.contentText,
    bookId: widget.bookId,
    chapterIndex: chapter.index,
  );

  /// Text of the page currently on screen, used to ground the companion line.
  String _pageText = '';

  Widget _decorateBody(
    Widget contentBody, {
    bool companionEnabled = true,
    String companionTooltip = '陪读',
    _CompanionWiring? companion,
  }) {
    if (_railPinned) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            ReaderRail(
              key: const Key('reader-rail-pinned'),
              pinned: true,
              onTogglePinned: _toggleRailPinned,
              onBackToLibrary: _backToLibrary,
              onOpenCompanion: _toggleCompanion,
              onOpenIllustration: _openIllustration,
              onOpenSettings: _openAppSettings,
              background: _colors.$1,
              foreground: _colors.$2,
              accent: _accent,
              companionEnabled: companionEnabled,
              companionTooltip: companionTooltip,
            ),
            Expanded(
              child: companionEnabled
                  ? _withAvatar(contentBody, companion: companion)
                  : contentBody,
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        companionEnabled
            ? _withAvatar(contentBody, companion: companion)
            : contentBody,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            key: const Key('reader-rail-hotzone'),
            onEnter: (_) => _showRail(),
            onExit: (_) => _suppressHotzone = false,
            child: const SizedBox(width: 12),
          ),
        ),
        if (_railVisible)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hideRailNow,
              child: const SizedBox.expand(),
            ),
          ),
        if (_railVisible)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              key: const Key('reader-rail-overlay'),
              onEnter: (_) => _showRail(),
              onExit: (_) => _scheduleHideRail(),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                builder: (context, value, child) =>
                    Opacity(opacity: value, child: child),
                child: ReaderRail(
                  pinned: false,
                  elevated: true,
                  onTogglePinned: _toggleRailPinned,
                  onBackToLibrary: _backToLibrary,
                  onOpenCompanion: _toggleCompanion,
                  onOpenIllustration: _openIllustration,
                  onOpenSettings: _openAppSettings,
                  background: _colors.$1,
                  foreground: _colors.$2,
                  accent: _accent,
                  companionEnabled: companionEnabled,
                  companionTooltip: companionTooltip,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Overlays the companion character on the reading area. It is placed after
  /// the page content (and therefore above the tap zones) so tapping it never
  /// turns the page.
  Widget _withAvatar(Widget content, {_CompanionWiring? companion}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = constraints.maxWidth < 720
            ? constraints.maxWidth
            : 720.0;
        final margin = (constraints.maxWidth - columnWidth) / 2;
        final roomy = margin >= 168;
        final height = roomy
            ? (constraints.maxHeight * 0.28).clamp(120.0, 200.0).toDouble()
            : 120.0;
        final bottom = roomy ? 24.0 : 12.0;
        final panelWidth = constraints.maxWidth - 24 < 320
            ? constraints.maxWidth - 24
            : 320.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned(
              right: 12,
              bottom: bottom,
              child: CompanionPresence(
                key: const Key('companion-presence'),
                height: height,
                greetingLoader: companion?.greetingLoader,
                onSpeak: companion?.onSpeak,
                onSpokenLine: companion?.onSpokenLine,
                onOpenChat: _toggleChat,
                pageTurns: _pageTurns,
              ),
            ),
            if (_chatOpen)
              Positioned(
                right: 12,
                bottom: bottom + height + 36,
                width: panelWidth,
                child: AnimatedBuilder(
                  animation: _chatController,
                  builder: (context, _) => CompanionChatPanel(
                    title: companion?.chatTitle ?? '陪读',
                    messages: _chatController.messagesFor(
                      companion?.chatChapterId ?? '',
                    ),
                    streaming: _chatController.streaming,
                    busy: _chatController.busy,
                    onSend: companion?.onChatSend ?? (_) {},
                    onClose: _toggleChat,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// One line about the page being read, cached per chapter so that paging
  /// inside a chapter does not re-ask the model.
  ///
  /// The cached line is keyed by the voice as well: switching from 温柔 to 思辨
  /// must not hand the reader a line written in the other temper.
  Future<String?> _companionGreeting(Chapter chapter, String pageText) async {
    await ref.read(personaModeProvider.notifier).ensureRestored();
    final persona = ref.read(personaModeProvider);
    return _greetings.putIfAbsent('${chapter.id}#${persona.id}', () {
      final offset =
          (_currentProgress()?.anchor.charOffset ?? chapter.startOffset) -
          chapter.startOffset;
      return ref.read(companionGreeterProvider)(
        CompanionGreetingRequest(
          bookId: widget.bookId,
          chapterIndex: chapter.index,
          chapterTitle: chapter.title,
          chapterText: chapter.contentText,
          pageText: pageText,
          readerOffset: offset < 0 ? 0 : offset,
          bookTitle: _cachedData?.book?.title ?? '',
          author: _cachedData?.book?.author ?? '',
        ),
      );
    });
  }

  Widget _buildComic(ReaderData data, String title) {
    final pagesAsync = ref.watch(comicPagesProvider(widget.bookId));
    return pagesAsync.when(
      loading: () => _scaffold(
        title: title,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _scaffold(
        title: title,
        body: Center(child: Text('漫画加载失败：$error')),
      ),
      data: (pages) {
        if (pages.isEmpty) {
          return _scaffold(
            title: title,
            body: const Center(child: Text('这本书没有可显示的漫画页面')),
          );
        }
        final total = pages.length;
        final doubleSpread = spreadApplies(
          _spread,
          MediaQuery.sizeOf(context).width,
        );
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
        final index = _comicDouble
            ? spreadPageIndex(_comicPageIndex)
            : _comicPageIndex.clamp(0, total - 1);
        _comicPageIndex = index;
        final percent = (index + 1) / total;
        final bookmarks =
            ref.watch(bookmarkListProvider(widget.bookId)).value ??
            const <Annotation>[];
        final pageBookmarked = bookmarks.any(
          (bookmark) => bookmark.anchorStart == index + 1,
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _colors.$1,
          appBar: ReaderTopBar(
            title: '$title · 第 ${index + 1} / $total 页',
            background: _colors.$1,
            foreground: _colors.$2,
            pinned: _railPinned,
            onTogglePinned: _toggleRailPinned,
            bookmarked: pageBookmarked,
            onToggleBookmark: () => _toggleComicBookmark(index + 1),
            onToggleSpread: _toggleSpread,
            doubleSpread: _comicDouble,
            comicMode: true,
            onOpenToc: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          endDrawer: ComicTocDrawer(
            pages: pages,
            currentIndex: index,
            bookmarks: bookmarks,
            onSelectPage: _goToComicPage,
            onSelectBookmark: (page) => _goToComicPage(page - 1),
            onDeleteBookmark: _deleteBookmark,
          ),
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _shiftComicSpread(-1),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _shiftComicSpread(1),
              const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                  _shiftComicSpread(-1),
              const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                  _shiftComicSpread(1),
            },
            child: Focus(
              autofocus: true,
              child: _decorateBody(
                PageView.builder(
                  key: const Key('comic-page-view'),
                  controller: _comicController,
                  itemCount: _comicDouble ? spreadCount(total) : total,
                  onPageChanged: _onComicPageChanged,
                  itemBuilder: (context, itemIndex) {
                    if (!_comicDouble) {
                      return _comicPage(pages[itemIndex], itemIndex);
                    }
                    final left = itemIndex * 2;
                    final right = left + 1;
                    return Row(
                      children: [
                        Expanded(child: _comicPage(pages[left], left)),
                        SizedBox(
                          width: kSpreadGutterWidth,
                          child: ColoredBox(color: _colors.$1),
                        ),
                        Expanded(
                          child: right < total
                              ? _comicPage(pages[right], right)
                              : const SizedBox.shrink(),
                        ),
                      ],
                    );
                  },
                ),
                companionEnabled: false,
                companionTooltip: '漫画暂不支持陪读',
              ),
            ),
          ),
          bottomNavigationBar: _comicNavigationBar(total, index, percent),
        );
      },
    );
  }

  Widget _comicPage(ComicPage page, int index) {
    return Center(
      child: Image.file(
        File(page.path),
        key: Key('comic-page-$index'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Text(
            '无法显示这一页',
            style: TextStyle(color: _colors.$2),
          ),
        ),
      ),
    );
  }

  void _onComicPageChanged(int itemIndex) {
    final total = _comicPageCount;
    if (total <= 0) return;
    final concrete = _comicDouble
        ? (itemIndex * 2).clamp(0, total - 1)
        : itemIndex.clamp(0, total - 1);
    if (!mounted || concrete == _comicPageIndex) return;
    setState(() => _comicPageIndex = concrete);
    _comicSaveTimer?.cancel();
    _comicSaveTimer = Timer(
      const Duration(milliseconds: 300),
      _persistComicProgress,
    );
  }

  void _goToComicPage(int index) {
    if (_comicPageCount <= 0) return;
    final target = index.clamp(0, _comicPageCount - 1);
    final controller = _comicController;
    if (controller != null && controller.hasClients) {
      controller.animateToPage(
        _comicDouble ? target ~/ 2 : target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    final concrete = _comicDouble ? spreadPageIndex(target) : target;
    if (concrete == _comicPageIndex) return;
    setState(() => _comicPageIndex = concrete);
    _comicSaveTimer?.cancel();
    _comicSaveTimer = Timer(
      const Duration(milliseconds: 300),
      _persistComicProgress,
    );
  }

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

  void _persistComicProgress() {
    final total = _comicPageCount;
    final repository = _progressRepository;
    if (total <= 0 || repository == null) return;
    final left = _comicDouble
        ? spreadPageIndex(_comicPageIndex)
        : _comicPageIndex;
    final page = left.clamp(0, total - 1) + 1;
    repository
        .save(
          ReadingProgress(
            bookId: widget.bookId,
            anchor: ReadingAnchor.page(page),
            percent: page / total,
            updatedAt: DateTime.now(),
          ),
        )
        .catchError((Object _) {});
  }

  Widget _comicNavigationBar(int total, int index, double percent) {
    final (background, foreground) = _colors;
    final step = _comicDouble ? 2 : 1;
    return Container(
      color: background,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0).toDouble(),
              minHeight: 3,
              backgroundColor: foreground.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(_accent),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: index - step >= 0
                        ? () => _shiftComicSpread(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一页'),
                    style: TextButton.styleFrom(foregroundColor: foreground),
                  ),
                  Expanded(
                    child: Text(
                      '第 ${index + 1} / $total 页 · '
                      '${(percent.clamp(0.0, 1.0) * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: index + step < total
                        ? () => _shiftComicSpread(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一页'),
                    style: TextButton.styleFrom(foregroundColor: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scaffold({
    required String title,
    Widget? body,
    Widget? endDrawer,
    Widget? bottomNavigationBar,
    bool? bookmarked,
    VoidCallback? onToggleBookmark,
    VoidCallback? onOpenAnnotations,
  }) {
    final (background, foreground) = _colors;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        title: Text(title),
        actions: [
          if (bookmarked != null && onToggleBookmark != null)
            IconButton(
              tooltip: '书签',
              icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
              onPressed: onToggleBookmark,
            ),
          if (onOpenAnnotations != null)
            IconButton(
              tooltip: '标注',
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: onOpenAnnotations,
            ),
          if (endDrawer != null)
            Builder(
              builder: (context) => IconButton(
                tooltip: '目录',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          IconButton(
            tooltip: '陪读',
            icon: const Icon(Icons.forum_outlined),
            onPressed: _toggleCompanion,
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.text_fields),
            onPressed: _openSettings,
          ),
        ],
      ),
      endDrawer: endDrawer,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
  }

  Widget _navigationBar(int index, List<Chapter> chapters) {
    final (background, foreground) = _colors;
    final pagination = _paginationChapterId == chapters[index].id
        ? _pagination
        : null;
    final pageCount = pagination?.pageCount ?? 1;
    final pageNumber = _pageIndex.clamp(0, pageCount - 1);
    final pageEndIndex = pagination == null ||
            !_doubleSpread ||
            _translationActive
        ? null
        : _pageEndIndex;
    final counts =
        _bookPageCountsSignature != null &&
            _bookPageCountsSignature == _bookPageSignature &&
            _bookPageCounts != null &&
            _bookPageCounts!.length == chapters.length
        ? _bookPageCounts
        : null;
    int? bookPageIndex;
    int? bookPageTotal;
    if (pagination != null && counts != null) {
      bookPageTotal = counts.fold<int>(0, (sum, count) => sum + count);
      bookPageIndex = bookPageAt(
        chapterPageCounts: counts,
        chapterIndex: index,
        pageIndex: pageNumber,
      );
    }
    final percent =
        (bookPageIndex != null && bookPageTotal != null && bookPageTotal > 0
                ? bookPageIndex / bookPageTotal
                : _currentProgress()?.percent ?? 0)
            .clamp(0.0, 1.0)
            .toDouble();
    final atBookStart = index == 0 && _pageIndex <= 0;
    final lastSpreadPage = _doubleSpread && !_translationActive
        ? spreadPageIndex(pageCount - 1)
        : pageCount - 1;
    final atBookEnd =
        index == chapters.length - 1 && _pageIndex >= lastSpreadPage;
    return Container(
      color: background,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: percent,
              minHeight: 3,
              backgroundColor: foreground.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(_accent),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: atBookStart ? null : _goToPreviousPage,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一页'),
                    style: TextButton.styleFrom(foregroundColor: foreground),
                  ),
                  Expanded(
                    child: Text(
                      key: const Key('reader-footer'),
                      readingFooterText(
                        pageIndex: pageNumber,
                        pageEndIndex: pageEndIndex,
                        chapterPageCount: pagination?.pageCount,
                        bookPageIndex: bookPageIndex,
                        bookPageTotal: bookPageTotal,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: atBookEnd ? null : _goToNextPage,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一页'),
                    style: TextButton.styleFrom(foregroundColor: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the reader page hands to the companion overlay: how to fetch a line,
/// how to route a chat message, and where that chat lives.
class _CompanionWiring {
  const _CompanionWiring({
    this.greetingLoader,
    this.onSpeak,
    this.onSpokenLine,
    this.onChatSend,
    this.chatChapterId,
    this.chatTitle,
  });

  final Future<String?> Function()? greetingLoader;
  final Future<String?> Function()? onSpeak;
  final ValueChanged<String>? onSpokenLine;
  final ValueChanged<String>? onChatSend;
  final String? chatChapterId;
  final String? chatTitle;
}
