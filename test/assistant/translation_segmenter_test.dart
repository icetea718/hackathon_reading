import 'package:flutter_test/flutter_test.dart';
import 'package:coread/assistant/translation_segmenter.dart';

void main() {
  group('TranslationSegmenter', () {
    test('rejects a non-positive limit', () {
      expect(() => TranslationSegmenter(maxChars: 0), throwsArgumentError);
    });

    test('keeps short paragraphs whole and drops blank lines', () {
      final segments = TranslationSegmenter().split('第一段\n\n  第二段  \n');
      expect(segments, ['第一段', '第二段']);
    });

    test('returns nothing for blank input', () {
      expect(TranslationSegmenter().split('   \n\n \t'), isEmpty);
    });

    test('splits a long paragraph on sentence boundaries', () {
      final text = List.filled(20, '这是一句很长的话。').join();
      final segments = TranslationSegmenter(maxChars: 30).split(text);

      expect(segments.length, greaterThan(1));
      expect(segments.every((segment) => segment.length <= 30), isTrue);
      expect(segments.every((segment) => segment.endsWith('。')), isTrue);
    });

    test('hard splits text without any sentence delimiter', () {
      final text = 'a' * 95;
      final segments = TranslationSegmenter(maxChars: 30).split(text);

      expect(segments.length, 4);
      expect(segments.every((segment) => segment.length <= 30), isTrue);
      expect(segments.join(), text);
    });

    test('never cuts a surrogate pair in half', () {
      final text = List.filled(20, '😀').join();
      final segments = TranslationSegmenter(maxChars: 9).split(text);

      expect(segments.every((segment) => segment.length <= 9), isTrue);
      expect(
        segments.every(
          (segment) => segment.runes.every((rune) => rune == 0x1F600),
        ),
        isTrue,
      );
    });
  });

  group('isPredominantlyChinese', () {
    test('accepts Chinese prose', () {
      expect(isPredominantlyChinese('这是一段中文，用来测试判断逻辑。'), isTrue);
    });

    test('accepts Chinese mixed with ascii digits', () {
      expect(isPredominantlyChinese('第 2 章：他走了 3 步。'), isTrue);
    });

    test('rejects English', () {
      expect(isPredominantlyChinese('The quick brown fox jumps'), isFalse);
    });

    test('rejects Japanese that contains kanji', () {
      expect(isPredominantlyChinese('吾輩は猫である。名前はまだ無い。'), isFalse);
    });

    test('rejects Korean', () {
      expect(isPredominantlyChinese('이것은 한국어 문장입니다.'), isFalse);
    });

    test('rejects text without letters', () {
      expect(isPredominantlyChinese('123 456。'), isFalse);
      expect(isPredominantlyChinese(''), isFalse);
    });
  });
}
