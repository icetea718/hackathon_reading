import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/annotation.dart';
import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/comic_page.dart';
import '../../domain/models/reading_progress.dart';
import '../annotations/annotations_page.dart';
import '../companion/companion_greeting.dart';
import '../companion/companion_panel.dart';
import '../companion/companion_presence.dart';
import '../settings/settings_page.dart';
import 'annotation_spans.dart';
import 'chapter_paginator.dart';
import 'comic_toc_drawer.dart';
import 'reader_position.dart';
import 'reader_providers.dart';
import 'reader_rail.dart';
import 'reader_settings_sheet.dart';
import 'reader_top_bar.dart';
import 'toc_drawer.dart';

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
  static const _railPinnedKey = 'reader.railPinned';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _chapterIndex = 0;
  int _pageIndex = 0;
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
  ProgressRepository? _progressRepository;
  SettingsRepository? _settingsRepository;
  PageController? _comicController;
  int _comicPageIndex = 0;
  int _comicPageCount = 0;
  bool _comicInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsRepository = ref.read(settingsRepositoryProvider);
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
      ]);
      if (!mounted) return;
      final fontSize = double.tryParse(values[0] ?? '');
      final lineHeight = double.tryParse(values[1] ?? '');
      final background = _backgroundFromName(values[2]);
      final railPinned = values[3];
      if (fontSize == null &&
          lineHeight == null &&
          background == null &&
          railPinned == null) {
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
  }

  @override
  void didChangeMetrics() {
    if (!_restored) return;
    final chapters = _cachedData?.chapters ?? const <Chapter>[];
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
    final chapter = data.chapters[index];
    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _pendingOffset = chapter.startOffset;
    });
    _scheduleProgressSave();
  }

  void _goToOffset(int charOffset) {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    final location = locateAnchor(data.chapters, charOffset);
    setState(() {
      _chapterIndex = location.chapterIndex;
      _pendingOffset = charOffset;
    });
    _scheduleProgressSave();
  }

  void _goToNextPage() {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    final pagination = _validPagination(data.chapters);
    if (pagination == null) return;
    if (_pageIndex < pagination.pageCount - 1) {
      setState(() => _pageIndex++);
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
    if (_pageIndex > 0) {
      setState(() => _pageIndex--);
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
      _pendingOffset = offset;
    });
    _scheduleProgressSave();
  }

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

  Future<void> _toggleBookmark(Chapter chapter) async {
    final repository = ref.read(annotationRepositoryProvider);
    try {
      final existing = (await repository.getForBook(
        widget.bookId,
        type: AnnotationType.bookmark,
      )).where((bookmark) => bookmark.chapterId == chapter.id).toList();

      if (existing.isNotEmpty) {
        for (final bookmark in existing) {
          await repository.delete(bookmark.id);
        }
        _refreshBookmarks();
        _showSnackBar('已取消书签');
        return;
      }

      final now = DateTime.now();
      final anchorStart =
          _currentProgress()?.anchor.charOffset ?? chapter.startOffset;
      await repository.upsert(
        Annotation(
          id: const Uuid().v4(),
          bookId: widget.bookId,
          chapterId: chapter.id,
          type: AnnotationType.bookmark,
          anchorStart: anchorStart,
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

  Future<void> _openCompanion() async {
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CompanionPanel(
        bookId: widget.bookId,
        chapterIndex: index,
        chapterTitle: chapter.title,
        chapterText: text,
        chapterCharOffset: offset < 0 ? 0 : offset,
        bookTitle: data.book?.title ?? '',
        author: data.book?.author ?? '',
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
              onChanged: (fontSize, lineHeight, background) {
                final chapters = _cachedData?.chapters ?? const <Chapter>[];
                final anchor = _currentPageStartOffset(chapters);
                setState(() {
                  if (anchor != null) _pendingOffset = anchor;
                  _fontSize = fontSize;
                  _lineHeight = lineHeight;
                  _background = background;
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
    return data.when(
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
        final chapterBookmarked = bookmarks.any(
          (bookmark) => bookmark.chapterId == currentChapter.id,
        );
        final chapterAnnotations = annotations
            .where((annotation) => annotation.chapterId == currentChapter.id)
            .toList();

        final contentBody = content.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('章节加载失败：$error')),
          data: (text) {
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
                final textWidth = (constraints.maxWidth.clamp(0.0, 720.0) - 40)
                    .clamp(1.0, 720.0);
                final textHeight = (constraints.maxHeight - 48).clamp(
                  1.0,
                  double.infinity,
                );
                final key =
                    '${currentChapter.id}|$_fontSize|$_lineHeight|'
                    '${textScaler.scale(1).toStringAsFixed(3)}|'
                    '${textWidth.round()}|${textHeight.round()}|${text.length}';
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
                    baseStyle: baseStyle,
                    width: textWidth,
                    height: textHeight,
                    textScaler: textScaler,
                  );
                  _pagination = pagination;
                  _paginationKey = key;
                  _paginationChapterId = currentChapter.id;
                }
                final bookSignature =
                    '$_fontSize|$_lineHeight|'
                    '${textScaler.scale(1).toStringAsFixed(3)}|'
                    '${textWidth.round()}|${textHeight.round()}|'
                    '${chapters.length}';
                if (bookSignature != _bookPageSignature) {
                  _bookPageSignature = bookSignature;
                  final layout = PageLayout(
                    baseStyle: baseStyle,
                    width: textWidth,
                    height: textHeight,
                    textScaler: textScaler,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _bookPageSignature != bookSignature) return;
                    _startBookPageCount(layout, chapters, bookSignature);
                  });
                }
                final pending = _pendingOffset;
                var pageIndex = pending != null
                    ? pagination.pageIndexForOffset(
                        pending - currentChapter.startOffset,
                      )
                    : _pageIndex;
                pageIndex = pageIndex.clamp(0, pagination.pageCount - 1);
                final page = pagination.pageAt(pageIndex);
                _pageIndex = pageIndex;
                _pendingOffset = null;
                _restored = true;
                if (pending != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }

                final spans = _pageSpans(
                  text: text,
                  page: page,
                  pagination: pagination,
                  chapter: currentChapter,
                  annotations: chapterAnnotations,
                  baseStyle: baseStyle,
                );
                final pageContent = text.substring(page.start, page.end);
                _pageText = pageContent;
                return Stack(
                  key: const Key('reader-page'),
                  fit: StackFit.expand,
                  children: [
                    Center(
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
                                    '${currentChapter.id}-$_pageIndex-$_paginationKey',
                                  ),
                                  child: SelectableText.rich(
                                    TextSpan(children: spans),
                                    contextMenuBuilder: (context, state) =>
                                        _selectionToolbar(
                                          state,
                                          page,
                                          pageContent,
                                          currentChapter,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: constraints.maxWidth * 0.3,
                      child: GestureDetector(
                        key: const Key('reader-prev-zone'),
                        behavior: HitTestBehavior.translucent,
                        onTap: _goToPreviousPage,
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
                        onTap: _goToNextPage,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );

        final body = _decorateBody(
          contentBody,
          greetingLoader: () => _companionGreeting(currentChapter, _pageText),
          onOpenChat: () => unawaited(_openCompanion()),
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
            bookmarked: chapterBookmarked,
            onToggleBookmark: () => _toggleBookmark(currentChapter),
            onOpenAnnotations: () => _openAnnotations(chapters),
            onOpenToc: () => _scaffoldKey.currentState?.openEndDrawer(),
            onOpenCompanion: _openCompanion,
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
          body: CallbackShortcuts(
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
          ),
          bottomNavigationBar: _navigationBar(index, chapters),
        );
      },
    );
  }

  /// Greeting lines already requested, keyed by chapter id.
  final Map<String, Future<String?>> _greetings = {};

  /// Text of the page currently on screen, used to ground the companion line.
  String _pageText = '';

  Widget _decorateBody(
    Widget contentBody, {
    bool companionEnabled = true,
    String companionTooltip = '陪读',
    Future<String?> Function()? greetingLoader,
    VoidCallback? onOpenChat,
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
              onOpenCompanion: _openCompanion,
              onOpenSettings: _openAppSettings,
              background: _colors.$1,
              foreground: _colors.$2,
              accent: _accent,
              companionEnabled: companionEnabled,
              companionTooltip: companionTooltip,
            ),
            Expanded(
              child: companionEnabled
                  ? _withAvatar(
                      contentBody,
                      greetingLoader: greetingLoader,
                      onOpenChat: onOpenChat,
                    )
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
            ? _withAvatar(
                contentBody,
                greetingLoader: greetingLoader,
                onOpenChat: onOpenChat,
              )
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
                  onOpenCompanion: _openCompanion,
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
  Widget _withAvatar(
    Widget content, {
    Future<String?> Function()? greetingLoader,
    VoidCallback? onOpenChat,
  }) {
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
        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned(
              right: 12,
              bottom: roomy ? 24 : 12,
              child: CompanionPresence(
                key: const Key('companion-presence'),
                height: height,
                greetingLoader: greetingLoader,
                onOpenChat: onOpenChat,
              ),
            ),
          ],
        );
      },
    );
  }

  /// One line about the page being read, cached per chapter so that paging
  /// inside a chapter does not re-ask the model.
  Future<String?> _companionGreeting(Chapter chapter, String pageText) {
    return _greetings.putIfAbsent(chapter.id, () {
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
        if (!_comicInitialized) {
          _comicInitialized = true;
          _comicPageCount = total;
          final saved = data.progress?.anchor.page ?? 1;
          _comicPageIndex = (saved - 1).clamp(0, total - 1);
          _comicController = PageController(initialPage: _comicPageIndex);
        } else if (_comicPageCount != total) {
          _comicPageCount = total;
          _comicPageIndex = _comicPageIndex.clamp(0, total - 1);
        }
        final index = _comicPageIndex.clamp(0, total - 1);
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
                  _goToComicPage(index - 1),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _goToComicPage(index + 1),
            },
            child: Focus(
              autofocus: true,
              child: _decorateBody(
                PageView.builder(
                  key: const Key('comic-page-view'),
                  controller: _comicController,
                  itemCount: total,
                  onPageChanged: _onComicPageChanged,
                  itemBuilder: (context, pageIndex) =>
                      _comicPage(pages[pageIndex], pageIndex),
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

  void _onComicPageChanged(int index) {
    if (!mounted || index == _comicPageIndex) return;
    setState(() => _comicPageIndex = index);
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
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    if (target == _comicPageIndex) return;
    setState(() => _comicPageIndex = target);
    _comicSaveTimer?.cancel();
    _comicSaveTimer = Timer(
      const Duration(milliseconds: 300),
      _persistComicProgress,
    );
  }

  void _persistComicProgress() {
    final total = _comicPageCount;
    final repository = _progressRepository;
    if (total <= 0 || repository == null) return;
    final page = _comicPageIndex.clamp(0, total - 1) + 1;
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
                    onPressed:
                        index > 0 ? () => _goToComicPage(index - 1) : null,
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
                    onPressed: index < total - 1
                        ? () => _goToComicPage(index + 1)
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
            onPressed: _openCompanion,
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
    final atBookEnd =
        index == chapters.length - 1 && _pageIndex >= pageCount - 1;
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
                      readingFooterText(
                        pageIndex: pageNumber,
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
