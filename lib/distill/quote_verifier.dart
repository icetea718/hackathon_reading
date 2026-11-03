/// Checks that a quoted sentence actually appears in the book text.
///
/// The index collapses all whitespace (including full-width spaces) so quotes
/// copied across line breaks still match.
class QuoteVerifier {
  QuoteVerifier(String bookText) : _text = _collapse(bookText);

  static const maxQuoteChars = 150;

  final String _text;

  bool contains(String quote) {
    if (quote.runes.length > maxQuoteChars) return false;
    final needle = _collapse(quote);
    if (needle.length < 2) return false;
    return _text.contains(needle);
  }

  static String _collapse(String input) {
    return input.replaceAll(RegExp(r'[\s\u3000]+'), '');
  }
}
