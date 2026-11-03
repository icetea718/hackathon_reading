import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/annotation.dart';
import 'package:hackathon_reading/features/reader/annotation_spans.dart';

Annotation _annotation({
  required int start,
  required int? end,
  AnnotationType type = AnnotationType.highlight,
  String? color = 'yellow',
  String note = '',
}) {
  final now = DateTime(2026, 1, 1);
  return Annotation(
    id: 'a-$start-$end',
    bookId: 'book',
    chapterId: 'c1',
    type: type,
    anchorStart: start,
    anchorEnd: end,
    color: color,
    noteText: note,
    createdAt: now,
    updatedAt: now,
  );
}

const _style = TextStyle(fontSize: 16);

List<InlineSpan> _spans(List<Annotation> annotations, {String text = '0123456789'}) {
  return buildAnnotationSpans(
    text: text,
    chapterStart: 100,
    annotations: annotations,
    baseStyle: _style,
  );
}

String _textOf(List<InlineSpan> spans) =>
    spans.map((span) => (span as TextSpan).text ?? '').join();

void main() {
  test('returns one plain span when there are no annotations', () {
    final spans = _spans(const []);

    expect(spans, hasLength(1));
    expect(_textOf(spans), '0123456789');
    expect((spans.single as TextSpan).style!.backgroundColor, isNull);
  });

  test('splits a highlight into before, highlight and after spans', () {
    final spans = _spans([
      _annotation(start: 103, end: 106),
    ]);

    expect(_textOf(spans), '0123456789');
    expect(spans, hasLength(3));
    expect(spans[1].toPlainText(), '345');
    expect(
      (spans[1] as TextSpan).style!.backgroundColor,
      highlightColorFor('yellow'),
    );
    expect((spans[0] as TextSpan).style!.backgroundColor, isNull);
  });

  test('clips highlights at the chapter boundaries', () {
    final spans = _spans([
      _annotation(start: 100, end: 102),
      _annotation(start: 108, end: 110),
    ]);

    expect(_textOf(spans), '0123456789');
    expect((spans.first as TextSpan).style!.backgroundColor,
        highlightColorFor('yellow'));
    expect((spans.last as TextSpan).text, '89');
    expect((spans.last as TextSpan).style!.backgroundColor,
        highlightColorFor('yellow'));
  });

  test('ignores annotations outside the chapter', () {
    final spans = _spans([
      _annotation(start: 90, end: 95),
      _annotation(start: 110, end: 115),
    ]);

    expect(spans, hasLength(1));
    expect(_textOf(spans), '0123456789');
  });

  test('clips overlapping highlights without duplicating text', () {
    final spans = _spans([
      _annotation(start: 102, end: 106, color: 'green'),
      _annotation(start: 104, end: 108, color: 'pink'),
    ]);

    expect(_textOf(spans), '0123456789');
    final highlighted = spans
        .whereType<TextSpan>()
        .where((span) => span.style?.backgroundColor != null)
        .toList();
    expect(highlighted.map((span) => span.text).join(), '234567');
    expect(highlighted.first.style!.backgroundColor, highlightColorFor('green'));
    expect(highlighted.last.style!.backgroundColor, highlightColorFor('pink'));
  });

  test('renders notes with a dotted underline and no background', () {
    final spans = _spans([
      _annotation(
        start: 104,
        end: 107,
        type: AnnotationType.note,
        color: null,
        note: '这里要再想想',
      ),
    ]);

    expect(_textOf(spans), '0123456789');
    final note = spans[1] as TextSpan;
    expect(note.text, '456');
    expect(note.style!.decoration, TextDecoration.underline);
    expect(note.style!.decorationStyle, TextDecorationStyle.dotted);
    expect(note.style!.backgroundColor, isNull);
  });

  test('ignores bookmarks and empty ranges', () {
    final spans = _spans([
      _annotation(start: 102, end: 105, type: AnnotationType.bookmark),
      _annotation(start: 106, end: 106),
      _annotation(start: 107, end: null),
    ]);

    expect(spans, hasLength(1));
    expect(_textOf(spans), '0123456789');
  });

  test('falls back to the default colour for unknown names', () {
    final spans = _spans([
      _annotation(start: 101, end: 103, color: 'unknown'),
    ]);

    expect(
      (spans[1] as TextSpan).style!.backgroundColor,
      highlightColorFor('yellow'),
    );
  });
}
