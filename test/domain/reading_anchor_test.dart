import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/reading_progress.dart';

void main() {
  test('reads legacy charOffset-only JSON', () {
    final anchor = ReadingAnchor.fromJson({'charOffset': 42});

    expect(anchor.charOffset, 42);
    expect(anchor.page, isNull);
  });

  test('round-trips a page anchor', () {
    const anchor = ReadingAnchor.page(3);

    expect(anchor.charOffset, 0);
    expect(anchor.page, 3);
    expect(ReadingAnchor.fromJson(anchor.toJson()).page, 3);
  });
}
