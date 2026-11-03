class PdfOutlineItem {
  const PdfOutlineItem({
    required this.title,
    this.pageNumber,
    this.children = const [],
  });

  final String title;
  final int? pageNumber;
  final List<PdfOutlineItem> children;
}

class PdfOutlineEntry {
  const PdfOutlineEntry({
    required this.title,
    required this.pageNumber,
    required this.depth,
  });

  final String title;
  final int pageNumber;
  final int depth;
}

List<PdfOutlineEntry> flattenPdfOutline(List<PdfOutlineItem> items) {
  final entries = <PdfOutlineEntry>[];

  void visit(List<PdfOutlineItem> nodes, int depth) {
    for (final node in nodes) {
      final pageNumber = node.pageNumber;
      final navigable = pageNumber != null && pageNumber > 0;
      if (navigable) {
        entries.add(PdfOutlineEntry(
          title: node.title,
          pageNumber: pageNumber,
          depth: depth,
        ));
      }
      visit(node.children, navigable ? depth + 1 : depth);
    }
  }

  visit(items, 0);
  return entries;
}
