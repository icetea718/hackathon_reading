import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/pdf_outline.dart';

void main() {
  test('flattens nested outline depth-first with page numbers', () {
    const items = [
      PdfOutlineItem(
        title: '第一章',
        pageNumber: 1,
        children: [
          PdfOutlineItem(title: '第一节', pageNumber: 2),
        ],
      ),
      PdfOutlineItem(title: '第二章', pageNumber: 5),
    ];

    final entries = flattenPdfOutline(items);

    expect(
      entries.map((entry) => '${entry.depth}:${entry.title}@${entry.pageNumber}'),
      ['0:第一章@1', '1:第一节@2', '0:第二章@5'],
    );
  });

  test('skips entries without a usable page but keeps their children', () {
    const items = [
      PdfOutlineItem(
        title: '外部链接',
        children: [
          PdfOutlineItem(title: '子章节', pageNumber: 3),
        ],
      ),
      PdfOutlineItem(title: '无效页码', pageNumber: 0),
    ];

    final entries = flattenPdfOutline(items);

    expect(entries, hasLength(1));
    expect(entries.single.title, '子章节');
    expect(entries.single.pageNumber, 3);
    expect(entries.single.depth, 0);
  });

  test('returns an empty list for a document without an outline', () {
    expect(flattenPdfOutline(const []), isEmpty);
  });
}
