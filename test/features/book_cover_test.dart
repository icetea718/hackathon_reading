import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/features/library/book_cover.dart';

Book bookFor(BookFormat format) => Book(
      id: 'b-${format.name}',
      title: '示例书',
      author: '',
      format: format,
      sourcePath: 'C:/books/a.${format.extension}',
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('falls back to a cover labelled with the format', (tester) async {
    for (final format in BookFormat.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 160,
              height: 220,
              child: BookCover(book: bookFor(format)),
            ),
          ),
        ),
      );

      final label = switch (format) {
        BookFormat.epub => 'EPUB',
        BookFormat.txt => 'TXT',
        BookFormat.pdf => 'PDF',
      };
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('falls back to a typeset title and the format label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 160,
            height: 220,
            child: BookCover(book: bookFor(BookFormat.txt)),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('示例书'));
    expect(title.maxLines, 2);
    expect(title.textAlign, TextAlign.center);
    expect(title.style?.fontFamily, 'Source Han Serif SC');
    expect(find.text('TXT'), findsOneWidget);
  });
}
