/// Overlapping two-character tokens of [text], punctuation dropped.
///
/// Used by both the pre-retrieval excerpt picker and the in-book searcher so a
/// question scores the same way wherever it is matched against prose.
Set<String> bigrams(String text) {
  final chars = text
      .replaceAll(RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]'), '')
      .toLowerCase()
      .runes
      .toList();
  final grams = <String>{};
  for (var i = 0; i + 1 < chars.length; i++) {
    grams.add(String.fromCharCodes([chars[i], chars[i + 1]]));
  }
  return grams;
}
