import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../memory_book/memory_book_models.dart';
import '../illustration/illustration_composer_page.dart';
import 'memory_book_dialogs.dart';
import 'memory_book_providers.dart';

class MemoryBookPage extends ConsumerStatefulWidget {
  const MemoryBookPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<MemoryBookPage> createState() => _MemoryBookPageState();
}

class _MemoryBookPageState extends ConsumerState<MemoryBookPage> {
  final PageController _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(memoryBookListProvider);
    MemoryBook? book;
    for (final item in async.value ?? const <MemoryBook>[]) {
      if (item.id == widget.bookId) {
        book = item;
        break;
      }
    }
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('回忆录')),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('这本回忆录不存在，或已经被删除。')),
      );
    }
    return _buildBook(book);
  }

  Widget _buildBook(MemoryBook book) {
    final hasPhotos = book.pages.isNotEmpty;
    final itemCount = 1 + (hasPhotos ? book.pages.length : 1) + 1;

    return Scaffold(
      backgroundColor: const Color(0xFF17120E),
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          IconButton(
            tooltip: '生成插画',
            onPressed: () => _openComposer(book),
            icon: const Icon(Icons.auto_awesome),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.2,
            colors: [Color(0xFF33271D), Color(0xFF120E0B)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxHeight = constraints.maxHeight * 0.9;
                  final pageWidth = math.min(
                    constraints.maxWidth * 0.78,
                    maxHeight * 3 / 4,
                  );
                  final pageHeight = pageWidth * 4 / 3;
                  return CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.arrowLeft):
                          _previous,
                      const SingleActivator(LogicalKeyboardKey.arrowRight):
                          _next,
                    },
                    child: Focus(
                      autofocus: true,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _controller,
                            itemCount: itemCount,
                            onPageChanged: (value) =>
                                setState(() => _current = value),
                            itemBuilder: (context, index) {
                              return Center(
                                child: SizedBox(
                                  width: pageWidth,
                                  height: pageHeight,
                                  child: _FlipPage(
                                    controller: _controller,
                                    index: index,
                                    child: _pageAt(book, index, itemCount),
                                  ),
                                ),
                              );
                            },
                          ),
                          Positioned(
                            left: 6,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _RailArrow(
                                icon: Icons.chevron_left,
                                tooltip: '上一页',
                                onPressed: _current > 0 ? _previous : null,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _RailArrow(
                                icon: Icons.chevron_right,
                                tooltip: '下一页',
                                onPressed:
                                    _current < itemCount - 1 ? _next : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _footer(book, itemCount),
          ],
        ),
      ),
    );
  }

  Widget _footer(MemoryBook book, int itemCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RailArrow(
            icon: Icons.chevron_left,
            tooltip: '上一页',
            onPressed: _current > 0 ? _previous : null,
          ),
          const SizedBox(width: 18),
          Text(
            _indicator(book, itemCount),
            style: const TextStyle(
              color: Color(0xFFB9A98E),
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 18),
          _RailArrow(
            icon: Icons.chevron_right,
            tooltip: '下一页',
            onPressed: _current < itemCount - 1 ? _next : null,
          ),
        ],
      ),
    );
  }

  String _indicator(MemoryBook book, int itemCount) {
    if (_current <= 0) return '封面';
    if (book.pages.isEmpty) {
      return _current >= itemCount - 1 ? '封底' : '还没有照片';
    }
    if (_current >= itemCount - 1) return '封底';
    final page = _current.clamp(1, book.pages.length);
    return '第 $page / ${book.pages.length} 页';
  }

  Widget _pageAt(MemoryBook book, int index, int itemCount) {
    if (index == 0) {
      return _CoverPage(book: book);
    }
    if (book.pages.isEmpty) {
      if (index == itemCount - 1) return const _EndPage();
      return _EmptyPage(onAdd: () => _openComposer(book));
    }
    if (index >= itemCount - 1) {
      return const _EndPage();
    }
    final page = book.pages[index - 1];
    return _PhotoPage(
      bookTitle: book.title,
      page: page,
      pageNumber: index,
      total: book.pages.length,
      onDelete: () => _deletePage(book, page),
      onMove: () => _movePage(book, page),
    );
  }

  void _previous() {
    if (!_controller.hasClients) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (!_controller.hasClients) return;
    _controller.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openComposer(MemoryBook book) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IllustrationComposerPage(preselectBookId: book.id),
      ),
    );
    if (added == true && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLastPage());
    }
  }

  void _jumpToLastPage() {
    if (!mounted || !_controller.hasClients) return;
    MemoryBook? latest;
    for (final item in ref.read(memoryBookListProvider).value ?? const []) {
      if (item.id == widget.bookId) {
        latest = item;
        break;
      }
    }
    if (latest == null) return;
    final target = latest.pages.isEmpty ? 1 : latest.pages.length;
    _controller.jumpToPage(target);
    setState(() => _current = target);
  }

  Future<void> _deletePage(MemoryBook book, MemoryPage page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这张照片？'),
        content: const Text('只从这本回忆录里删除，原图文件也会一起删掉。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final store = await ref.read(memoryBookStoreProvider.future);
      await store.deletePage(book.id, page.id);
      _clampCurrentPage(book.pages.length - 1);
    } catch (error) {
      if (!mounted) return;
      _snack('删除失败：$error');
    }
  }

  Future<void> _movePage(MemoryBook book, MemoryPage page) async {
    final target = await pickMoveTargetDialog(
      context,
      ref,
      sourceBookId: book.id,
    );
    if (target == null || !mounted) return;
    try {
      final store = await ref.read(memoryBookStoreProvider.future);
      await store.movePage(
        fromBookId: book.id,
        pageId: page.id,
        toBookId: target,
      );
      _clampCurrentPage(book.pages.length - 1);
      _snack('已移动到另一本回忆录');
    } catch (error) {
      if (!mounted) return;
      _snack('移动失败：$error');
    }
  }

  void _clampCurrentPage(int photoCount) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final itemCount = 1 + (photoCount == 0 ? 1 : photoCount) + 1;
      final target = _current.clamp(0, itemCount - 1).toInt();
      _controller.jumpToPage(target);
      setState(() => _current = target);
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FlipPage extends StatelessWidget {
  const _FlipPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = controller.hasClients
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        final delta = index - current;
        final angle =
            (delta.clamp(-1.0, 1.0) * (math.pi / 2) * 0.45).toDouble();
        if (angle.abs() < 0.002) return child;
        return Transform(
          alignment:
              delta >= 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..rotateY(angle),
          child: child,
        );
      },
      child: child,
    );
  }
}

class _RailArrow extends StatelessWidget {
  const _RailArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFFD6C3A2),
        backgroundColor: Colors.black26,
      ),
    );
  }
}

class _CoverPage extends StatelessWidget {
  const _CoverPage({required this.book});

  final MemoryBook book;

  static const _serifFallbacks = [
    'Noto Serif CJK SC',
    'SimSun',
    'Georgia',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3C4A40), Color(0xFF1A231E)],
        ),
        border: Border.all(color: const Color(0xFF131A16), width: 10),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x88C8AA78)),
                ),
              ),
            ),
            const SizedBox(height: 36),
            const Text(
              '回 忆 录',
              style: TextStyle(
                color: Color(0xFFEADCC2),
                fontSize: 30,
                letterSpacing: 8,
                fontFamily: 'Source Han Serif SC',
                fontFamilyFallback: _serifFallbacks,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              book.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB9A887),
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 76,
              height: 1,
              color: const Color(0x66B08D57),
            ),
            const SizedBox(height: 16),
            Text(
              '${book.pageCount} 张照片 · ${book.dateLabel}',
              style: const TextStyle(
                color: Color(0xFF8D7E66),
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPage extends StatelessWidget {
  const _PhotoPage({
    required this.bookTitle,
    required this.page,
    required this.pageNumber,
    required this.total,
    required this.onDelete,
    required this.onMove,
  });

  final String bookTitle;
  final MemoryPage page;
  final int pageNumber;
  final int total;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final meta = page.medium.isEmpty
        ? page.dateLabel
        : '${page.dateLabel} · ${page.medium}';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4ECDD),
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x77000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color: const Color(0xFFFFFDF7),
                    padding: const EdgeInsets.all(10),
                    child: Image.file(
                      File(page.imagePath),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Color(0xFFA08F76),
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  meta,
                  style: const TextStyle(
                    color: Color(0xFF6D5C46),
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
                if (page.excerpt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    page.excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8E7D64),
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$pageNumber / $total',
                    style: const TextStyle(
                      color: Color(0xFFA08F76),
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: PopupMenuButton<String>(
              tooltip: '这张照片',
              icon: const Icon(
                Icons.more_horiz,
                size: 20,
                color: Color(0xFF6D5C46),
              ),
              onSelected: (value) {
                if (value == 'delete') onDelete();
                if (value == 'move') onMove();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'delete', child: Text('删除这张照片')),
                PopupMenuItem(value: 'move', child: Text('移动到其他回忆录…')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4ECDD),
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x77000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.photo_outlined,
            size: 42,
            color: Color(0xFFA08F76),
          ),
          const SizedBox(height: 14),
          const Text(
            '还没有照片',
            style: TextStyle(
              color: Color(0xFF6C5B45),
              fontSize: 20,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '生成一张插画，收进这本回忆录。',
            style: TextStyle(color: Color(0xFF94836B), fontSize: 12),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('添加第一张插画'),
          ),
        ],
      ),
    );
  }
}

class _EndPage extends StatelessWidget {
  const _EndPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F3B34), Color(0xFF1A231E)],
        ),
        border: Border.all(color: const Color(0xFF131A16), width: 10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Text(
          '未 完 待 续',
          style: TextStyle(
            color: Color(0xFFB9A887),
            fontSize: 14,
            letterSpacing: 6,
          ),
        ),
      ),
    );
  }
}
