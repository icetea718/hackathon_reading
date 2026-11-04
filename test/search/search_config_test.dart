import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/settings_repository.dart';
import 'package:coread/search/search_config.dart';

void main() {
  test('免费源不需要 Key，Tavily 需要', () {
    expect(const SearchConfig(provider: SearchConfig.free).isConfigured, isTrue);
    expect(const SearchConfig(provider: SearchConfig.free).isEnabled, isTrue);
    expect(const SearchConfig(provider: SearchConfig.free).requiresApiKey, isFalse);
    expect(const SearchConfig(provider: SearchConfig.tavily).requiresApiKey, isTrue);
    expect(const SearchConfig(provider: SearchConfig.tavily).isConfigured, isFalse);
    expect(const SearchConfig().isConfigured, isFalse);
  });

  test('provider = free 且带 key 时仍以免费源为准', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SearchConfigStore(SettingsRepository(db));

    await store.save(const SearchConfig(provider: SearchConfig.free, apiKey: ''));
    final restored = await store.load();

    expect(restored.provider, 'free');
    expect(restored.isEnabled, isTrue);
  });
}
