import 'package:flutter_test/flutter_test.dart';
import 'package:coread/assistant/cached_translation_service.dart';
import 'package:coread/assistant/translation_exception.dart';

import '../support/fake_assistant_service.dart';
import '../support/fake_translation_cache.dart';

void main() {
  test('translates once and remembers the result', () async {
    final inner = FakeAssistantService(chunks: const ['你好', '，世界']);
    final cache = FakeTranslationCache();
    final service = CachedTranslationService(inner: inner, cache: cache);

    final first = await service.translate('Hello', targetLang: 'zh-CN').toList();
    final second =
        await service.translate('Hello', targetLang: 'zh-CN').toList();

    expect(first, ['你好', '，世界']);
    expect(second, ['你好，世界']);
    expect(inner.translatedSources, ['Hello']);
    expect(cache.entries['zh-CN|Hello'], '你好，世界');
  });

  test('keeps languages apart', () async {
    final inner = FakeAssistantService(chunks: const ['译']);
    final cache = FakeTranslationCache();
    final service = CachedTranslationService(inner: inner, cache: cache);

    await service.translate('Hello', targetLang: 'zh-CN').toList();
    await service.translate('Hello', targetLang: 'ja').toList();

    expect(inner.translatedSources, ['Hello', 'Hello']);
    expect(cache.entries.keys, containsAll(['zh-CN|Hello', 'ja|Hello']));
  });

  test('does not remember a failed translation', () async {
    final inner = FakeAssistantService(
      error: const TranslationException('网络连接失败，请检查网络后重试'),
    );
    final cache = FakeTranslationCache();
    final service = CachedTranslationService(inner: inner, cache: cache);

    await expectLater(
      service.translate('Hello', targetLang: 'zh-CN'),
      emitsError(isA<TranslationException>()),
    );
    expect(cache.entries, isEmpty);
  });

  test('still works when the cache throws', () async {
    final inner = FakeAssistantService(chunks: const ['译文']);
    final service = CachedTranslationService(
      inner: inner,
      cache: _BrokenCache(),
    );

    expect(
      await service.translate('Hello', targetLang: 'zh-CN').toList(),
      ['译文'],
    );
  });
}

class _BrokenCache extends FakeTranslationCache {
  @override
  Future<String?> find(String sourceText, {required String targetLang}) {
    throw StateError('cache down');
  }
}
