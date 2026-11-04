/// One paragraph of a chapter, anchored to its character offset in the
/// chapter text, together with its translation.
class TranslationBlock {
  const TranslationBlock({
    required this.start,
    required this.source,
    required this.translation,
  });

  /// Offset of the paragraph's first visible character within the chapter.
  final int start;
  final String source;
  final String translation;

  TranslationBlock withTranslation(String translated) {
    return TranslationBlock(
      start: start,
      source: source,
      translation: translated,
    );
  }
}

/// Splits chapter text into non-empty lines, each becoming one translation
/// block. Lines (rather than sentences) keep a paragraph's translation on the
/// page where the paragraph starts, independent of later re-pagination.
List<TranslationBlock> splitTranslationBlocks(String text) {
  final blocks = <TranslationBlock>[];
  for (final match in RegExp(r'[^\r\n]+').allMatches(text)) {
    final line = match.group(0)!;
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final leading = line.indexOf(trimmed);
    blocks.add(
      TranslationBlock(
        start: match.start + leading,
        source: trimmed,
        translation: '',
      ),
    );
  }
  return blocks;
}

/// The blocks that begin inside `[start, end)`, matching what a page shows.
List<TranslationBlock> blocksForRange(
  List<TranslationBlock> blocks,
  int start,
  int end,
) {
  return blocks
      .where((block) => block.start >= start && block.start < end)
      .toList();
}
