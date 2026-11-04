/// Splits long source text into pieces a single translation request can handle,
/// preferring paragraph and sentence boundaries over hard cuts.
class TranslationSegmenter {
  TranslationSegmenter({this.maxChars = 480}) {
    if (maxChars <= 0) {
      throw ArgumentError.value(maxChars, 'maxChars', 'must be positive');
    }
  }

  /// Maximum length of a single piece, in UTF-16 code units.
  final int maxChars;

  static const String _sentenceDelimiters = '。！？!?；;';

  /// Splits [text] into translation-sized pieces, dropping blank lines.
  List<String> split(String text) {
    final segments = <String>[];
    for (final block in text.split(RegExp(r'\r?\n'))) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;
      segments.addAll(_splitBlock(trimmed));
    }
    return segments;
  }

  List<String> _splitBlock(String block) {
    if (block.length <= maxChars) return [block];

    final result = <String>[];
    final buffer = StringBuffer();
    for (final sentence in _sentences(block)) {
      if (sentence.length > maxChars) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString().trim());
          buffer.clear();
        }
        result.addAll(_hardSplit(sentence));
        continue;
      }
      if (buffer.length + sentence.length > maxChars) {
        result.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.write(sentence);
    }
    if (buffer.isNotEmpty) result.add(buffer.toString().trim());
    return result.where((segment) => segment.isNotEmpty).toList();
  }

  Iterable<String> _sentences(String block) sync* {
    var start = 0;
    for (var index = 0; index < block.length; index++) {
      if (!_endsSentence(block, index)) continue;
      final end = index + 1;
      yield block.substring(start, end);
      start = end;
    }
    if (start < block.length) yield block.substring(start);
  }

  bool _endsSentence(String block, int index) {
    final char = block[index];
    if (_sentenceDelimiters.contains(char)) return true;
    // A latin full stop only ends a sentence when whitespace or the end of the
    // block follows it, so decimals and abbreviations stay intact.
    if (char == '.' && index + 1 < block.length) {
      return block[index + 1] == ' ' || block[index + 1] == '\t';
    }
    return false;
  }

  /// Cuts a sentence that is longer than [maxChars] without splitting surrogate
  /// pairs (so emoji and rare CJK characters stay intact).
  List<String> _hardSplit(String sentence) {
    final pieces = <String>[];
    var start = 0;
    while (start < sentence.length) {
      var end = start + maxChars;
      if (end >= sentence.length) {
        end = sentence.length;
      } else if (_isLowSurrogate(sentence.codeUnitAt(end))) {
        end -= 1;
      }
      final piece = sentence.substring(start, end).trim();
      if (piece.isNotEmpty) pieces.add(piece);
      start = end;
    }
    return pieces;
  }

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

/// Whether [text] reads as Chinese already, so translating it is pointless.
///
/// Japanese and Korean are deliberately excluded: kana or hangul characters
/// mark the text as a language that still needs translating.
bool isPredominantlyChinese(String text) {
  var han = 0;
  var kanaOrHangul = 0;
  var otherLetters = 0;

  for (final rune in text.runes) {
    if (_isKana(rune)) {
      kanaOrHangul++;
    } else if (_isHangul(rune)) {
      kanaOrHangul++;
    } else if (_isHan(rune)) {
      han++;
    } else if (_isLetter(rune)) {
      otherLetters++;
    }
  }

  final total = han + kanaOrHangul + otherLetters;
  if (total == 0 || kanaOrHangul > 0) return false;
  return han / total >= 0.6;
}

bool _isHan(int rune) =>
    (rune >= 0x4E00 && rune <= 0x9FFF) || (rune >= 0x3400 && rune <= 0x4DBF);

bool _isKana(int rune) =>
    (rune >= 0x3040 && rune <= 0x30FF) || (rune >= 0x31F0 && rune <= 0x31FF);

bool _isHangul(int rune) =>
    (rune >= 0xAC00 && rune <= 0xD7AF) || (rune >= 0x1100 && rune <= 0x11FF);

bool _isLetter(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A) ||
    (rune >= 0xC0 && rune <= 0x24F) ||
    (rune >= 0x370 && rune <= 0x3FF) ||
    (rune >= 0x400 && rune <= 0x4FF);
