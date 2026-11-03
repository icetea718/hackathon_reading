import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../data/repositories/progress_repository.dart';
import '../../domain/models/annotation.dart';
import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/reading_progress.dart';
import '../annotations/annotations_page.dart';
import '../companion/companion_panel.dart';
import 'annotation_spans.dart';
import 'reader_position.dart';
import 'reader_providers.dart';
import 'reader_settings_sheet.dart';
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
            decoration: InputDecoration(
              hintText: '写下你的想法',
              errorText: _error,
            ),
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
  final ScrollController _scrollController = ScrollController();
  int _chapterIndex = 0;
  double _fontSize = 18;
  double _lineHeight = 1.6;
  ReaderBackground _background = ReaderBackground.light;
  bool _restoreScheduled = false;
  bool _restored = false;
  bool _restoreInFlight = false;
  ResumeLocation? _pendingRestore;
  Timer? _saveTimer;
  ReaderData? _cachedData;
  ProgressRepository? _progressRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _persistProgress();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!_restored) return;
    final anchor = _currentProgress()?.anchor.charOffset;
    if (anchor != null) _reanchorAfterLayout(anchor);
  }

  void _onScroll() {
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
    final index = _chapterIndex < 0
        ? 0
        : (_chapterIndex >= chapters.length
            ? chapters.length - 1
            : _chapterIndex);
    final chapter = chapters[index];
    final max = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final fraction = max <= 0
        ? 0.0
        : (_scrollController.offset / max).clamp(0.0, 1.0).toDouble();
    final charOffset = anchorOffsetForFraction(chapter, fraction);
    final total = chapters.last.endOffset;
    final percent =
        total <= 0 ? 0.0 : (charOffset / total).clamp(0.0, 1.0).toDouble();

    return ReadingProgress(
      bookId: widget.bookId,
      anchor: ReadingAnchor(charOffset: charOffset),
      percent: percent,
      updatedAt: DateTime.now(),
    );
  }

  void _scheduleRestore(ReaderData data) {
    if (_restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (data.chapters.isNotEmpty) {
        final anchor = data.progress?.anchor.charOffset ?? 0;
        final location = locateAnchor(data.chapters, anchor);
        _pendingRestore = location;
        setState(() => _chapterIndex = location.chapterIndex);
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

  void _schedulePendingRestore() {
    final pending = _pendingRestore;
    if (pending == null || _restoreInFlight) return;
    _restoreInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreInFlight = false;
      if (!mounted || !_scrollController.hasClients) return;
      _pendingRestore = null;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(max * pending.fraction);
      _restored = true;
    });
  }

  void _reanchorAfterLayout(int charOffset) {
    final data = _cachedData;
    if (data == null || data.chapters.isEmpty) return;
    final location = locateAnchor(data.chapters, charOffset);
    _pendingRestore = location;
    if (location.chapterIndex != _chapterIndex) {
      setState(() => _chapterIndex = location.chapterIndex);
    }
    _schedulePendingRestore();
  }

  void _goToChapter(int index, List<Chapter> chapters) {
    if (index < 0 || index >= chapters.length) return;
    setState(() => _chapterIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _restored = true;
      _persistProgress();
    });
  }

  (Color, Color) get _colors {
    return switch (_background) {
      ReaderBackground.light => (
          const Color(0xFFFAFAF7),
          const Color(0xFF1B1B1B),
        ),
      ReaderBackground.sepia => (
          const Color(0xFFF4ECD8),
          const Color(0xFF3B2F1E),
        ),
      ReaderBackground.dark => (
          const Color(0xFF15161A),
          const Color(0xFFE4E4E4),
        ),
    };
  }

  Future<void> _toggleBookmark(Chapter chapter) async {
    final repository = ref.read(annotationRepositoryProvider);
    try {
      final existing = (await repository.getForBook(
        widget.bookId,
        type: AnnotationType.bookmark,
      ))
          .where((bookmark) => bookmark.chapterId == chapter.id)
          .toList();

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
      await repository.upsert(Annotation(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        chapterId: chapter.id,
        type: AnnotationType.bookmark,
        anchorStart: anchorStart,
        createdAt: now,
        updatedAt: now,
      ));
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
    TextSelection selection,
    String text,
  ) async {
    final color = await _pickHighlightColor();
    if (color == null || !mounted) return;
    await _saveSelectionAnnotation(
      chapter,
      selection,
      text,
      (anchorStart, anchorEnd, selectedText) =>
          ref.read(annotationServiceProvider).addHighlight(
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
      selection,
      text,
      (anchorStart, anchorEnd, text) =>
          ref.read(annotationServiceProvider).addNote(
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
    TextSelection selection,
    String text,
    Future<void> Function(int anchorStart, int anchorEnd, String selectedText)
        save, {
    required String successMessage,
  }) async {
    if (!selection.isValid || selection.isCollapsed) return;
    try {
      await save(
        chapter.startOffset + selection.start,
        chapter.startOffset + selection.end,
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

  Future<void> _openAnnotations(List<Chapter> chapters) async {
    final anchor = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => AnnotationsPage(
          bookId: widget.bookId,
          chapters: chapters,
        ),
      ),
    );
    if (anchor == null || !mounted) return;
    _refreshAnnotations();
    _reanchorAfterLayout(anchor);
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

  Future<String?> _pickHighlightColor() {    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择高亮颜色'),
              ),
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
              _highlightSelection(chapter, selection, text);
            },
          ),
          ContextMenuButtonItem(
            label: '笔记',
            onPressed: () {
              editableTextState.hideToolbar();
              _addNote(chapter, selection, text);
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
                final anchor = _currentProgress()?.anchor.charOffset;
                setState(() {
                  _fontSize = fontSize;
                  _lineHeight = lineHeight;
                  _background = background;
                });
                setSheet(() {});
                if (anchor != null) _reanchorAfterLayout(anchor);
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
        final chapterBookmarked =
            bookmarks.any((bookmark) => bookmark.chapterId == currentChapter.id);
        final chapterAnnotations = annotations
            .where((annotation) => annotation.chapterId == currentChapter.id)
            .toList();

        return _scaffold(
          title: title,
          bookmarked: chapterBookmarked,
          onToggleBookmark: () => _toggleBookmark(currentChapter),
          onOpenAnnotations: () => _openAnnotations(chapters),
          drawer: TocDrawer(
            chapters: chapters,
            currentIndex: index,
            currentChapterId: currentChapter.id,
            bookmarks: bookmarks,
            onSelect: (selected) => _goToChapter(selected, chapters),
            onSelectBookmark: _reanchorAfterLayout,
            onDeleteBookmark: _deleteBookmark,
          ),
          body: content.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('章节加载失败：$error')),
            data: (text) {
              _schedulePendingRestore();
              final baseStyle = TextStyle(
                fontSize: _fontSize,
                height: _lineHeight,
                color: _colors.$2,
              );
              final spans = buildAnnotationSpans(
                text: text,
                chapterStart: currentChapter.startOffset,
                annotations: chapterAnnotations,
                baseStyle: baseStyle,
              );
              return SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: SelectableText.rich(
                  TextSpan(children: spans),
                  contextMenuBuilder: (context, editableTextState) =>
                      _selectionToolbar(
                    editableTextState,
                    text,
                    currentChapter,
                  ),
                ),
              );
            },
          ),
          bottomNavigationBar: _navigationBar(index, chapters),
        );
      },
    );
  }

  Widget _scaffold({
    required String title,
    Widget? body,
    Widget? drawer,
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
              icon: Icon(
                bookmarked ? Icons.bookmark : Icons.bookmark_border,
              ),
              onPressed: onToggleBookmark,
            ),
          if (onOpenAnnotations != null)
            IconButton(
              tooltip: '标注',
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: onOpenAnnotations,
            ),
          if (drawer != null)
            Builder(
              builder: (context) => IconButton(
                tooltip: '目录',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
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
      drawer: drawer,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
  }

  Widget _navigationBar(int index, List<Chapter> chapters) {
    final (background, foreground) = _colors;
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: index > 0
                  ? () => _goToChapter(index - 1, chapters)
                  : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一章'),
              style: TextButton.styleFrom(foregroundColor: foreground),
            ),
            Expanded(
              child: Text(
                '${index + 1} / ${chapters.length}',
                textAlign: TextAlign.center,
                style: TextStyle(color: foreground),
              ),
            ),
            TextButton.icon(
              onPressed: index < chapters.length - 1
                  ? () => _goToChapter(index + 1, chapters)
                  : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一章'),
              style: TextButton.styleFrom(foregroundColor: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
