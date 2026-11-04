import '../../data/repositories/settings_repository.dart';

/// Immutable LLM connection settings.
///
/// An empty or blank [apiKey] means "not configured": callers must not issue
/// requests in that case.
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.temperature = defaultTemperature,
    this.maxChunkChars = defaultMaxChunkChars,
  });

  static const defaultTemperature = 0.3;
  static const defaultMaxChunkChars = 6000;

  /// OpenAI-compatible endpoint root, without a trailing slash.
  final String baseUrl;
  final String model;
  final String apiKey;
  final double temperature;

  /// Upper bound for a single distillation chunk, in characters.
  final int maxChunkChars;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  static const baseUrlKey = 'llm.baseUrl';
  static const modelKey = 'llm.model';
  static const apiKeyKey = 'llm.apiKey';
  static const temperatureKey = 'llm.temperature';
  static const maxChunkCharsKey = 'llm.maxChunkChars';

  static const defaults = LlmConfig(
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    apiKey: '',
  );

  LlmConfig copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
    double? temperature,
    int? maxChunkChars,
  }) {
    return LlmConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      temperature: temperature ?? this.temperature,
      maxChunkChars: maxChunkChars ?? this.maxChunkChars,
    );
  }

  @override
  String toString() =>
      'LlmConfig(baseUrl: $baseUrl, model: $model, configured: $isConfigured)';
}

/// Reads and writes [LlmConfig] through the settings table.
class LlmConfigStore {
  LlmConfigStore(this._settings);

  final SettingsRepository _settings;

  Future<LlmConfig> load() async {
    final baseUrl = await _settings.get(LlmConfig.baseUrlKey);
    final model = await _settings.get(LlmConfig.modelKey);
    final apiKey = await _settings.get(LlmConfig.apiKeyKey);
    final temperature = await _settings.get(LlmConfig.temperatureKey);
    final maxChunkChars = await _settings.get(LlmConfig.maxChunkCharsKey);

    return LlmConfig(
      baseUrl: _nonEmpty(baseUrl) ?? LlmConfig.defaults.baseUrl,
      model: _nonEmpty(model) ?? LlmConfig.defaults.model,
      apiKey: apiKey ?? '',
      temperature:
          _parseDouble(temperature) ?? LlmConfig.defaults.temperature,
      maxChunkChars:
          _parseInt(maxChunkChars) ?? LlmConfig.defaults.maxChunkChars,
    );
  }

  Future<void> save(LlmConfig config) async {
    await _settings.set(LlmConfig.baseUrlKey, config.baseUrl);
    await _settings.set(LlmConfig.modelKey, config.model);
    await _settings.set(LlmConfig.apiKeyKey, config.apiKey);
    await _settings.set(LlmConfig.temperatureKey, '${config.temperature}');
    await _settings.set(
      LlmConfig.maxChunkCharsKey,
      '${config.maxChunkChars}',
    );
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _parseDouble(String? value) {
    if (value == null) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > 2) return null;
    return parsed;
  }

  static int? _parseInt(String? value) {
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 500) return null;
    return parsed;
  }
}
