import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/tts/speech_text.dart';

void main() {
  group('speechText', () {
    test('drops stage directions and Markdown emphasis', () {
      expect(
        speechText('【轻声】你好，**福贵**，`老牛`。<laugh>'),
        '你好，福贵，老牛。',
      );
    });

    test('keeps bracketed prose that is too long to be a tag', () {
      final prose = '＜${'很长的一段旁白' * 10}＞';
      expect(speechText(prose), contains('很长的一段旁白'));
    });

    test('collapses newlines and repeated spaces', () {
      expect(speechText('第一行\n\n  第二行'), '第一行 第二行');
    });
  });

  group('ttsSafe', () {
    test('strips emoji and decorative symbols but keeps punctuation', () {
      expect(ttsSafe('好耶♡★♪！真的吗？'), '好耶！真的吗？');
      expect(ttsSafe('看这个 😀 表情'), '看这个 表情');
    });

    test('ttsPlain keeps only letters, digits and spaces', () {
      expect(ttsPlain('好耶！真的吗？ok 123'), '好耶真的吗ok 123');
    });
  });

  group('promptLanguageOf', () {
    test('recognises the four scripts', () {
      expect(promptLanguageOf('今天天气不错'), 'zh');
      expect(promptLanguageOf('こんにちは'), 'ja');
      expect(promptLanguageOf('안녕하세요'), 'ko');
      expect(promptLanguageOf('hello there'), 'en');
    });
  });

  group('splitSpeech', () {
    test('returns nothing for blank input', () {
      expect(splitSpeech('   \n '), isEmpty);
    });

    test('splits at sentence endings', () {
      expect(
        splitSpeech('福贵输了钱。家珍哭了！老牛还在。'),
        ['福贵输了钱。', '家珍哭了！', '老牛还在。'],
      );
    });

    test('wraps a long sentence below the chunk size', () {
      final long = '${'这是一句很长的旁白，' * 12}结束。';
      final chunks = splitSpeech(long, maxChars: 40);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(40));
      }
      expect(chunks.join(), long);
    });
  });
}
