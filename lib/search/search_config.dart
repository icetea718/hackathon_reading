import '../data/repositories/settings_repository.dart';

/// Web-search settings, stored in the same `settings` table as the LLM config.
///
/// [provider] is `'off'` or `'tavily'`; an empty key also counts as off.
class SearchConfig {
  const SearchConfig({this.provider = off, this.apiKey = ''});

  static const off = 'off';
  static const tavily = 'tavily';

  final String provider;
  final String apiKey;

  bool get isConfigured => provider != off && apiKey.trim().isNotEmpty;

  /// Whether the 搜 shell should attempt retrieval for a question.
  bool get isEnabled => isConfigured;

  static const providerKey = 'search.provider';
  static const apiKeyKey = 'search.apiKey';

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
}
