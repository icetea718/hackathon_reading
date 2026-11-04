import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/reader/chapter_translation.dart';

void main() {
  group('splitTranslationBlocks', () {
    test('keeps one block per non-empty line with its offset', () {
      final blocks = splitTranslationBlocks('First\n\nSecond line\n');

      expect(blocks.map((block) => block.source), ['First', 'Second line']);
      expect(blocks.map((block) => block.start), [0, 7]);
    });

    test('points at the first visible character of an indented line', () {
      final blocks = splitTranslationBlocks('  Indented\nNext');

      expect(blocks.map((block) => block.start), [2, 11]);
    });

    test('returns nothing for blank text', () {
      expect(splitTranslationBlocks('  \n\n'), isEmpty);
    });
  });

  group('blocksForRange', () {
    final blocks = splitTranslationBlocks('A\nB\nC');

    test('keeps the blocks that start inside the range', () {
      expect(
        blocksForRange(blocks, 2, 3).map((block) => block.source),
        ['B'],
      );
    });

    test('treats the end of the range as exclusive', () {
      expect(blocksForRange(blocks, 0, 2).map((block) => block.source), ['A']);
    });
  });

  group('TranslationBlock.withTranslation', () {
    test('returns a copy carrying the translated text', () {
      final block = TranslationBlock(start: 4, source: 'Hello', translation: '');
      final translated = block.withTranslation('你好');

      expect(translated.start, 4);
      expect(translated.source, 'Hello');
      expect(translated.translation, '你好');
    });
  });
}
