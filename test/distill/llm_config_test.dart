import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/settings_repository.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';

void main() {
  late AppDatabase db;
  late LlmConfigStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = LlmConfigStore(SettingsRepository(db));
  });

  tearDown(() => db.close());

  test('defaults have no api key and are not configured', () {
    expect(LlmConfig.defaults.isConfigured, isFalse);
    expect(LlmConfig.defaults.baseUrl, 'https://api.deepseek.com/v1');
    expect(LlmConfig.defaults.model, 'deepseek-chat');
    expect(LlmConfig.defaults.temperature, 0.3);
  });

  test('an empty or blank api key is not configured', () {
    const config = LlmConfig(
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      apiKey: '   ',
    );

    expect(config.isConfigured, isFalse);
  });

  test('store round-trips config through settings', () async {
    await store.save(
      const LlmConfig(
        baseUrl: 'http://localhost:8080/v1',
        model: 'custom-model',
        apiKey: 'sk-test',
        temperature: 0.5,
        maxChunkChars: 3000,
      ),
    );

    final loaded = await store.load();

    expect(loaded.baseUrl, 'http://localhost:8080/v1');
    expect(loaded.model, 'custom-model');
    expect(loaded.apiKey, 'sk-test');
    expect(loaded.temperature, 0.5);
    expect(loaded.maxChunkChars, 3000);
    expect(loaded.isConfigured, isTrue);
  });

  test('load falls back to defaults when nothing is stored', () async {
    final loaded = await store.load();

    expect(loaded.baseUrl, LlmConfig.defaults.baseUrl);
    expect(loaded.model, LlmConfig.defaults.model);
    expect(loaded.apiKey, '');
    expect(loaded.isConfigured, isFalse);
  });

  test('malformed numeric values fall back to defaults', () async {
    final settings = SettingsRepository(db);
    await settings.set(LlmConfig.temperatureKey, 'hot');
    await settings.set(LlmConfig.maxChunkCharsKey, 'lots');

    final loaded = await store.load();

    expect(loaded.temperature, LlmConfig.defaults.temperature);
    expect(loaded.maxChunkChars, LlmConfig.defaults.maxChunkChars);
  });
}
