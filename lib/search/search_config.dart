import '../data/repositories/settings_repository.dart';

/// Web-search settings, stored in the same `settings` table as the LLM config.
///
/// [provider] is `'off'` | `'free'` | `'tavily'`; an empty key also counts as
/// off for providers that need one.
class SearchConfig {
  const SearchConfig({this.provider = off, this.apiKey = ''});

  static const off = 'off';
  static const free = 'free';
  static const tavily = 'tavily';

  final String provider;
  final String apiKey;

  /// Tavily 需要一个 Key；免 Key 的源返回 false。
  bool get requiresApiKey => provider == tavily;

  bool get isConfigured =>
      provider != off && (!requiresApiKey || apiKey.trim().isNotEmpty);

  /// Whether the 搜 shell should attempt retrieval for a question.
  bool get isEnabled => isConfigured;

  static const providerKey = 'search.provider';
  static const apiKeyKey = 'search.apiKey';

  /// Whether 搜 may let the model call the book tools. On unless turned off.
  static const toolsEnabledKey = 'search.toolsEnabled';

  /// Set when an endpoint rejected `tools`; the 搜 shell then stays classic.
  static String toolsUnsupportedKey(String model) =>
      'search.toolsUnsupported.$model';

  SearchConfig copyWith({String? provider, String? apiKey}) => SearchConfig(
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
      );

  @override
  bool operator ==(Object other) =>
      other is SearchConfig &&
      other.provider == provider &&
      other.apiKey == apiKey;

  @override
  int get hashCode => Object.hash(provider, apiKey);

  @override
  String toString() =>
      'SearchConfig(provider: $provider, configured: $isConfigured)';
}

class SearchConfigStore {
  SearchConfigStore(this._settings);

  final SettingsRepository _settings;

  Future<SearchConfig> load() async {
    final provider = (await _settings.get(SearchConfig.providerKey))?.trim();
    final apiKey = await _settings.get(SearchConfig.apiKeyKey);
    return SearchConfig(
      provider: provider == null || provider.isEmpty
          ? SearchConfig.off
          : provider,
      apiKey: apiKey ?? '',
    );
  }

  Future<void> save(SearchConfig config) async {
    await _settings.set(SearchConfig.providerKey, config.provider);
    await _settings.set(SearchConfig.apiKeyKey, config.apiKey);
  }

  /// Tool calling defaults on; only an explicit `'false'` turns it off.
  Future<bool> toolsEnabled() async {
    final raw = (await _settings.get(SearchConfig.toolsEnabledKey))
        ?.trim()
        .toLowerCase();
    return raw != 'false';
  }

  Future<void> setToolsEnabled(bool enabled) => _settings.set(
        SearchConfig.toolsEnabledKey,
        enabled ? 'true' : 'false',
      );

  /// Whether [model] already rejected a `tools` request.
  Future<bool> isToolsUnsupported(String model) async {
    final raw = await _settings.get(SearchConfig.toolsUnsupportedKey(model));
    return raw?.trim() == 'true';
  }

  Future<void> markToolsUnsupported(String model) =>
      _settings.set(SearchConfig.toolsUnsupportedKey(model), 'true');
}
