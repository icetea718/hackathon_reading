import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../data/repositories/progress_repository.dart';
import '../../domain/models/annotation.dart';
import '../../domain/models/book.dart';
import '../../domain/models/reading_progress.dart';
import 'pdf_outline_drawer.dart';
import 'pdf_reader_providers.dart';
import 'reader_providers.dart';

class PdfReaderPage extends ConsumerStatefulWidget {
  const PdfReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  final PdfViewerController _controller = PdfViewerController();
  PdfBookInfo? _info;
  ReadingProgress? _progress;
  ProgressRepository? _progressRepository;
  Timer? _saveTimer;
  int? _pageNumber;
  int? _initialPage;
  bool _viewerReady = false;
  bool _openedRecorded = false;

  @override
  void dispose() {
    _saveTimer?.cancel();
    _persistProgress();
    super.dispose();
  }

  int _clampPage(int page, int pageCount) {
    if (pageCount <= 0) return 1;
    if (page < 1) return 1;
    if (page > pageCount) return pageCount;
    return page;
  }

  int _currentPage(PdfBookInfo info) {
    final page = _pageNumber ?? _initialPage ?? 1;
    return _clampPage(page, info.pageCount);
  }

  void _onPageChanged(int? page) {
    final info = _info;
    if (page == null || info == null) return;
    final next = _clampPage(page, info.pageCount);
    if (next == _pageNumber) return;
    setState(() => _pageNumber = next);
    _scheduleSave();
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted) return;
    setState(() => _viewerReady = true);
  }

  void _goToPage(int page) {
    final info = _info;
    if (info == null) return;
    final target = _clampPage(page, info.pageCount);
    setState(() => _pageNumber = target);
    if (_controller.isReady) {
      _controller.goToPage(pageNumber: target);
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _persistProgress);
  }

  void _persistProgress() {
    final info = _info;
    final repository = _progressRepository;
    if (info == null || repository == null || info.pageCount <= 0) return;
    final page = _currentPage(info);
    repository
        .save(ReadingProgress(
          bookId: widget.bookId,
          anchor: ReadingAnchor.page(page),
          percent: page / info.pageCount,
          updatedAt: DateTime.now(),
        ))
        .catchError((Object _) {});
  }

  void _recordOpened(Book? book) {
    if (_openedRecorded || book == null) return;
    _openedRecorded = true;
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
    ref.read(bookRepositoryProvider).upsert(opened).catchError((Object _) {});
  }

  Future<void> _toggleBookmark(int page) async {
    final repository = ref.read(annotationRepositoryProvider);
    try {
      final existing = (await repository.getForBook(
        widget.bookId,
        type: AnnotationType.bookmark,
      ))
          .where((bookmark) => bookmark.anchorStart == page)
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
      await repository.upsert(Annotation(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        type: AnnotationType.bookmark,
        anchorStart: page,
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showPageJump(int pageCount, int currentPage) async {
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _PageJumpDialog(
        pageCount: pageCount,
        initialPage: currentPage,
      ),
    );
    if (target != null) _goToPage(target);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(readerDataProvider(widget.bookId));
    final info = ref.watch(pdfBookInfoProvider(widget.bookId));

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
        _progress = readerData.progress;
        _recordOpened(readerData.book);
        return info.when(
          loading: () => _scaffold(
            title: readerData.book?.title ?? '阅读',
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _scaffold(
            title: readerData.book?.title ?? '阅读',
            body: Center(child: Text('PDF 加载失败：$error')),
          ),
          data: (bookInfo) {
            _info = bookInfo;
            _progressRepository ??= ref.read(progressRepositoryProvider);
            _initialPage ??= _clampPage(
              _progress?.anchor.page ?? 1,
              bookInfo.pageCount,
            );
            final book = readerData.book;
            if (book == null) {
              return _scaffold(
                title: '阅读',
                body: const Center(child: Text('这本书不存在')),
              );
            }

            final currentPage = _currentPage(bookInfo);
            final bookmarks =
                ref.watch(bookmarkListProvider(widget.bookId)).value ??
                    const <Annotation>[];
            final bookmarked =
                bookmarks.any((bookmark) => bookmark.anchorStart == currentPage);
            final viewer = ref.watch(pdfViewerBuilderProvider);
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading:
                    Navigator.of(context).canPop() ? const BackButton() : null,
                title: Text(book.title),
                actions: [
                  IconButton(
                    tooltip: '书签',
                    icon: Icon(
                      bookmarked ? Icons.bookmark : Icons.bookmark_border,
                    ),
                    onPressed: () => _toggleBookmark(currentPage),
                  ),
                  IconButton(
                    tooltip: '缩小',
                    icon: const Icon(Icons.zoom_out),
                    onPressed: _viewerReady
                        ? () => _controller.zoomDown()
                        : null,
                  ),
                  IconButton(
                    tooltip: '放大',
                    icon: const Icon(Icons.zoom_in),
                    onPressed:
                        _viewerReady ? () => _controller.zoomUp() : null,
                  ),
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: '目录',
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                ],
              ),
              drawer: PdfOutlineDrawer(
                pageCount: bookInfo.pageCount,
                outline: bookInfo.outline,
                currentPage: currentPage,
                bookmarks: bookmarks,
                onSelectPage: _goToPage,
                onSelectBookmark: _goToPage,
                onDeleteBookmark: _deleteBookmark,
              ),
              body: viewer(
                context,
                path: book.sourcePath,
                controller: _controller,
                initialPageNumber: _initialPage!,
                onPageChanged: _onPageChanged,
                onViewerReady: _onViewerReady,
              ),
              bottomNavigationBar: _pageBar(bookInfo.pageCount, currentPage),
            );
          },
        );
      },
    );
  }

  Widget _scaffold({required String title, required Widget body}) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        title: Text(title),
      ),
      body: body,
    );
  }

  Widget _pageBar(int pageCount, int page) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: page > 1 ? () => _goToPage(page - 1) : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一页'),
            ),
            Expanded(
              child: Tooltip(
                message: '跳转页码',
                child: TextButton(
                  onPressed: () => _showPageJump(pageCount, page),
                  child: Text('$page / $pageCount'),
                ),
              ),
            ),
            TextButton.icon(
              onPressed:
                  page < pageCount ? () => _goToPage(page + 1) : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一页'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageJumpDialog extends StatefulWidget {
  const _PageJumpDialog({required this.pageCount, required this.initialPage});

  final int pageCount;
  final int initialPage;

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.initialPage}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final page = int.tryParse(_controller.text.trim());
    if (page == null || page < 1 || page > widget.pageCount) {
      setState(() => _error = '请输入 1 到 ${widget.pageCount} 之间的页码');
      return;
    }
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('跳转页码'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: '页码',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
