import 'package:coread/data/repositories/translation_cache_repository.dart';

/// In-memory [TranslationCacheStore] for widget tests.
class FakeTranslationCache implements TranslationCacheStore {
  FakeTranslationCache([Map<String, String>? seed])
      : _entries = {...?seed};

  final Map<String, String> _entries;
  int lookups = 0;
  int saves = 0;
  int removals = 0;

  static String _key(String sourceText, String targetLang) =>
      '$targetLang|$sourceText';

  Map<String, String> get entries => Map.unmodifiable(_entries);

  @override
  Future<String?> find(String sourceText, {required String targetLang}) async {
    lookups++;
    return _entries[_key(sourceText, targetLang)];
  }

  @override
  Future<void> save(
    String sourceText, {
    required String targetLang,
    required String translatedText,
  }) async {
    saves++;
    _entries[_key(sourceText, targetLang)] = translatedText;
  }

  @override
  Future<void> remove(String sourceText, {required String targetLang}) async {
    removals++;
    _entries.remove(_key(sourceText, targetLang));
  }
}
