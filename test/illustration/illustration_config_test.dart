import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';
import 'package:hackathon_reading/illustration/illustration_config.dart';

void main() {
  const llm = LlmConfig(
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    model: 'doubao-seed-2-1-pro-260915',
    apiKey: 'ark-test-key',
  );

  test('inherits base url and key from the global AI config', () {
    final effective = const IllustrationConfig().resolve(llm);

    expect(effective.baseUrl, llm.baseUrl);
    expect(effective.apiKey, 'ark-test-key');
    expect(effective.chatModel, IllustrationConfig.defaultChatModel);
    expect(effective.imageModel, IllustrationConfig.defaultImageModel);
    expect(effective.isConfigured, isTrue);
    expect(effective.isDeepSeek, isFalse);
  });

  test('own base url and key override the global config', () {
    const config = IllustrationConfig(
      baseUrl: 'https://ark.ap-southeast.volces.com/api/v3',
      apiKey: 'own-key',
      chatModel: 'custom-chat',
      imageModel: 'custom-image',
    );
    final effective = config.resolve(llm);

    expect(effective.baseUrl, config.baseUrl);
    expect(effective.apiKey, 'own-key');
    expect(effective.chatModel, 'custom-chat');
    expect(effective.imageModel, 'custom-image');
    expect(effective.looksLikeArk, isTrue);
  });

  test('detects DeepSeek and missing keys', () {
    const deepseek = LlmConfig(
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      apiKey: 'sk-test',
    );
    final withDeepSeek = const IllustrationConfig().resolve(deepseek);
    expect(withDeepSeek.isDeepSeek, isTrue);
    expect(withDeepSeek.isConfigured, isTrue);

    const emptyKey = LlmConfig(
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      apiKey: '',
    );
    final unconfigured = const IllustrationConfig().resolve(emptyKey);
    expect(unconfigured.isConfigured, isFalse);
  });
}
