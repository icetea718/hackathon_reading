import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/my_memory_translator.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/assistant/translation_exception.dart';
import 'package:hackathon_reading/assistant/translation_segmenter.dart';

class _RecordingBackend implements TranslationBackend {
  _RecordingBackend({this.failOn});

  final String? failOn;
  final List<String> texts = [];
  final List<String> languagePairs = [];

  @override
  Future<String> translate(String text, {required String langPair}) async {
    texts.add(text);
    languagePairs.add(langPair);
    if (text == failOn) {
      throw const TranslationException('网络连接失败，请检查网络后重试');
    }
    return '译：$text';
  }
}

void main() {
  group('MyMemoryTranslator', () {
    test('reports itself as configured', () {
      final translator = MyMemoryTranslator(backend: _RecordingBackend());
      expect(translator.isConfigured, isTrue);
    });

    test('translates every chunk in order and asks for simplified Chinese', () async {
      final backend = _RecordingBackend();
      final translator = MyMemoryTranslator(
        backend: backend,
        segmenter: TranslationSegmenter(maxChars: 30),
        requestInterval: Duration.zero,
      );

      final chunks = await translator
          .translate('First paragraph here.\nSecond paragraph here.',
              targetLang: 'zh-CN')
          .toList();

      expect(chunks, [
        '译：First paragraph here.',
        '\n译：Second paragraph here.',
      ]);
      expect(backend.languagePairs, ['autodetect|zh-CN', 'autodetect|zh-CN']);
    });

    test('passes already-Chinese chunks through untouched', () async {
      final backend = _RecordingBackend();
      final translator = MyMemoryTranslator(
        backend: backend,
        requestInterval: Duration.zero,
      );

      final chunks = await translator
          .translate('这是中文。\nThis is English.', targetLang: 'zh-CN')
          .toList();

      expect(chunks, ['这是中文。', '\n译：This is English.']);
      expect(backend.texts, ['This is English.']);
    });

    test('surfaces backend failures as stream errors', () async {
      final backend = _RecordingBackend(failOn: 'boom');
      final translator = MyMemoryTranslator(
        backend: backend,
        requestInterval: Duration.zero,
      );

      await expectLater(
        translator.translate('boom', targetLang: 'zh-CN'),
        emitsError(
          isA<TranslationException>().having(
            (error) => error.message,
            'message',
            '网络连接失败，请检查网络后重试',
          ),
        ),
      );
    });

    test('keeps the other abilities unconfigured', () async {
      final translator = MyMemoryTranslator(backend: _RecordingBackend());
      const context = ReadingContext(bookTitle: '围城', chapterText: '正文');

      await expectLater(
        translator.explain('方鸿渐', context: context),
        emitsError(isA<AssistantNotConfiguredException>()),
      );
      await expectLater(
        translator.summarizeChapter(context),
        emitsError(isA<AssistantNotConfiguredException>()),
      );
      await expectLater(
        translator.chat(context, const [], '你好'),
        emitsError(isA<AssistantNotConfiguredException>()),
      );
    });
  });

  group('parseMyMemoryBody', () {
    test('reads the translated text', () {
      const body = '{"responseData":{"translatedText":"你好世界"},'
          '"responseStatus":200,"responseDetails":""}';
      expect(parseMyMemoryBody(body), '你好世界');
    });

    test('reports the daily quota warning', () {
      const body = '{"responseData":{"translatedText":'
          '"MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS"},'
          '"responseStatus":200}';
      expect(
        () => parseMyMemoryBody(body),
        throwsA(
          isA<TranslationException>().having(
            (error) => error.message,
            'message',
            contains('今日免费翻译额度已用完'),
          ),
        ),
      );
    });

    test('explains that Chinese input needs no translation', () {
      const body = '{"responseData":{"translatedText":'
          '"PLEASE SELECT TWO DISTINCT LANGUAGES"},'
          '"responseStatus":403,'
          '"responseDetails":"PLEASE SELECT TWO DISTINCT LANGUAGES"}';
      expect(
        () => parseMyMemoryBody(body),
        throwsA(
          isA<TranslationException>().having(
            (error) => error.message,
            'message',
            '原文已是中文，无需翻译',
          ),
        ),
      );
    });

    test('rejects unparsable payloads', () {
      expect(
        () => parseMyMemoryBody('<html>oops</html>'),
        throwsA(isA<TranslationException>()),
      );
    });

    test('rejects an empty translation', () {
      const body = '{"responseData":{"translatedText":""},"responseStatus":200}';
      expect(
        () => parseMyMemoryBody(body),
        throwsA(isA<TranslationException>()),
      );
    });
  });
}
