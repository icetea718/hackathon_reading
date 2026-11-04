import '../data/repositories/settings_repository.dart';
import '../distill/llm/llm_config.dart';

/// 插画/绘图服务的独立配置。
///
/// 聊天和绘图在火山方舟 Ark 下共用一把 Key，但模型 ID 不同，所以这里
/// 单独保存 `chatModel` 和 `imageModel`。接口地址/Key 留空时回退到全局
/// [LlmConfig]，方便“一把 Ark Key 走天下”的用法。
class IllustrationConfig {
  const IllustrationConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.chatModel = defaultChatModel,
    this.imageModel = defaultImageModel,
  });

  static const defaultChatModel = 'doubao-seed-2-1-pro-260915';
  static const defaultImageModel = 'doubao-seedream-5-0-pro-260628';

  static const defaults = IllustrationConfig();

  static const baseUrlKey = 'illustration.baseUrl';
  static const apiKeyKey = 'illustration.apiKey';
  static const chatModelKey = 'illustration.chatModel';
  static const imageModelKey = 'illustration.imageModel';

  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String imageModel;

  bool get hasOwnKey => apiKey.trim().isNotEmpty;

  IllustrationEffective resolve(LlmConfig llm) {
    final base = baseUrl.trim().isEmpty ? llm.baseUrl.trim() : baseUrl.trim();
    final key = apiKey.trim().isEmpty ? llm.apiKey.trim() : apiKey.trim();
    final chat = chatModel.trim().isEmpty ? llm.model : chatModel.trim();
    return IllustrationEffective(
      baseUrl: base,
      apiKey: key,
      chatModel: chat,
      imageModel: imageModel.trim(),
    );
  }

  @override
  String toString() =>
      'IllustrationConfig(baseUrl: $baseUrl, chat: $chatModel, '
      'image: $imageModel, ownKey: $hasOwnKey)';
}

class IllustrationEffective {
  const IllustrationEffective({
    required this.baseUrl,
    required this.apiKey,
    required this.chatModel,
    required this.imageModel,
  });

  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String imageModel;

  bool get isConfigured =>
      apiKey.isNotEmpty && baseUrl.isNotEmpty && imageModel.isNotEmpty;

  bool get looksLikeArk => baseUrl.contains('volces.com');

  bool get isDeepSeek => baseUrl.contains('deepseek.com');

  LlmConfig get chatConfig => LlmConfig(
        baseUrl: baseUrl,
        model: chatModel,
        apiKey: apiKey,
        temperature: 0.4,
      );

  @override
  String toString() =>
      'IllustrationEffective(baseUrl: $baseUrl, chat: $chatModel, '
      'image: $imageModel, configured: $isConfigured)';
}

/// 通过 `settings` 表读写插画配置，不新增数据库表。
class IllustrationConfigStore {
  IllustrationConfigStore(this._settings);

  final SettingsRepository _settings;

  Future<IllustrationConfig> load() async {
    final baseUrl = await _settings.get(IllustrationConfig.baseUrlKey);
    final apiKey = await _settings.get(IllustrationConfig.apiKeyKey);
    final chatModel = await _settings.get(IllustrationConfig.chatModelKey);
    final imageModel = await _settings.get(IllustrationConfig.imageModelKey);

    return IllustrationConfig(
      baseUrl: baseUrl?.trim() ?? '',
      apiKey: apiKey ?? '',
      chatModel: _nonEmpty(chatModel) ?? IllustrationConfig.defaultChatModel,
      imageModel: _nonEmpty(imageModel) ?? IllustrationConfig.defaultImageModel,
    );
  }

  Future<void> save(IllustrationConfig config) async {
    await _settings.set(IllustrationConfig.baseUrlKey, config.baseUrl.trim());
    await _settings.set(IllustrationConfig.apiKeyKey, config.apiKey.trim());
    await _settings.set(
      IllustrationConfig.chatModelKey,
      config.chatModel.trim(),
    );
    await _settings.set(
      IllustrationConfig.imageModelKey,
      config.imageModel.trim(),
    );
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
