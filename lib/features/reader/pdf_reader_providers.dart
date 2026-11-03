import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/providers.dart';
import '../../domain/models/book.dart';
import '../../domain/models/pdf_outline.dart';

class PdfBookInfo {
  const PdfBookInfo({required this.pageCount, required this.outline});

  final int pageCount;
  final List<PdfOutlineEntry> outline;
}

final pdfBookInfoProvider = FutureProvider.family<PdfBookInfo, String>(
  (ref, bookId) async {
    final book = await ref.watch(bookRepositoryProvider).getById(bookId);
    if (book == null || book.format != BookFormat.pdf) {
      throw StateError('Not a PDF book: $bookId');
    }

    final document = await PdfDocument.openFile(book.sourcePath);
    try {
      final outline = await document.loadOutline();
      return PdfBookInfo(
        pageCount: document.pages.length,
        outline: flattenPdfOutline(_toOutlineItems(outline)),
      );
    } finally {
      await document.dispose();
    }
  },
);

typedef PdfViewerBuilder = Widget Function(
  BuildContext context, {
  required String path,
  required PdfViewerController controller,
  required int initialPageNumber,
  required ValueChanged<int?> onPageChanged,
  required void Function(PdfDocument document, PdfViewerController controller)
      onViewerReady,
});

final pdfViewerBuilderProvider = Provider<PdfViewerBuilder>((ref) {
  return (
    context, {
    required path,
    required controller,
    required initialPageNumber,
    required onPageChanged,
    required onViewerReady,
  }) {
    return PdfViewer.file(
      path,
      controller: controller,
      initialPageNumber: initialPageNumber,
      params: PdfViewerParams(
        backgroundColor: const Color(0xFFE9E9E9),
        onPageChanged: onPageChanged,
        onViewerReady: onViewerReady,
      ),
    );
  };
});

List<PdfOutlineItem> _toOutlineItems(List<PdfOutlineNode> nodes) {
  return [
    for (final node in nodes)
      PdfOutlineItem(
        title: node.title,
        pageNumber: node.dest?.pageNumber,
        children: _toOutlineItems(node.children),
      ),
  ];
}
