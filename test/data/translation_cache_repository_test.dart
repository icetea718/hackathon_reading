import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/translation_cache_repository.dart';

void main() {
  late AppDatabase db;
  late TranslationCacheRepository cache;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cache = TranslationCacheRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('stores and reads back a translation', () async {
    await cache.save(
      'Hello world',
      targetLang: 'zh-CN',
      translatedText: '你好世界',
    );

    expect(
      await cache.find('Hello world', targetLang: 'zh-CN'),
      '你好世界',
    );
  });

  test('returns null for text that was never translated', () async {
    expect(await cache.find('unknown', targetLang: 'zh-CN'), isNull);
  });

  test('overwrites the entry when the same text is translated again', () async {
    await cache.save('Hi', targetLang: 'zh-CN', translatedText: '旧译文');
    await cache.save('Hi', targetLang: 'zh-CN', translatedText: '新译文');

    expect(await cache.find('Hi', targetLang: 'zh-CN'), '新译文');
  });

  test('keeps languages apart', () async {
    await cache.save('Hi', targetLang: 'zh-CN', translatedText: '你好');
    await cache.save('Hi', targetLang: 'ja', translatedText: 'こんにちは');

    expect(await cache.find('Hi', targetLang: 'zh-CN'), '你好');
    expect(await cache.find('Hi', targetLang: 'ja'), 'こんにちは');
    expect(await cache.find('Hi', targetLang: 'fr'), isNull);
  });

  test('removes an entry', () async {
    await cache.save('Hi', targetLang: 'zh-CN', translatedText: '你好');
    await cache.remove('Hi', targetLang: 'zh-CN');

    expect(await cache.find('Hi', targetLang: 'zh-CN'), isNull);
  });

  test('hashes identical text to the same key', () {
    expect(
      translationSourceHash('同一段文字'),
      translationSourceHash('同一段文字'),
    );
    expect(
      translationSourceHash('第一段'),
      isNot(translationSourceHash('第二段')),
    );
  });
}
