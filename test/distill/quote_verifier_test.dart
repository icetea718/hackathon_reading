import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/distill/quote_verifier.dart';

void main() {
  test('matches a quote that spans a line break in the source', () {
    final verifier = QuoteVerifier('福贵牵着老牛\n走在田埂上。');

    expect(verifier.contains('福贵牵着老牛走在田埂上'), isTrue);
  });

  test('matches despite full-width spaces and indentation', () {
    final verifier = QuoteVerifier('第一段。\n　　第二段　开始了。');

    expect(verifier.contains('第二段开始了'), isTrue);
  });

  test('rejects quotes that are not in the text', () {
    final verifier = QuoteVerifier('福贵牵着老牛走在田埂上');

    expect(verifier.contains('家珍在灶前烧火'), isFalse);
  });

  test('rejects quotes longer than 150 characters', () {
    final long = '字' * 200;
    final verifier = QuoteVerifier(long);

    expect(verifier.contains(long), isFalse);
    expect(verifier.contains('字' * 150), isTrue);
  });

  test('rejects degenerate quotes', () {
    final verifier = QuoteVerifier('福贵牵着老牛');

    expect(verifier.contains(''), isFalse);
    expect(verifier.contains('  '), isFalse);
  });
}
