import '../data/repositories/settings_repository.dart';

/// Where the companion voice comes from and how it should sound.
///
/// The endpoint is a GPT-SoVITS `api_v2` server, which speaks the OpenAI
/// `/audio/speech` shape — the same one the reference Coopanion plugin exposes.
class TtsConfig {
  const TtsConfig({
    required this.baseUrl,
    required this.voice,
    required this.speed,
    required this.volume,
    required this.enabled,
    required this.autoSpeak,
  });

  static const String baseUrlKey = 'tts.baseUrl';
  static const String voiceKey = 'tts.voice';
  static const String speedKey = 'tts.speed';
  static const String volumeKey = 'tts.volume';
  static const String enabledKey = 'tts.enabled';
  static const String autoSpeakKey = 'tts.autoSpeak';

  /// Preset voices shipped by the reference plugin.
  static const List<String> voicePresets = ['xll', 'dfy', 'female', 'male'];

  static const TtsConfig defaults = TtsConfig(
    baseUrl: 'http://127.0.0.1:9880',
    voice: 'xll',
    speed: 1,
    volume: 1,
    enabled: true,
    autoSpeak: false,
  );

  final String baseUrl;
  final String voice;

  /// Speaking rate, 0.6–1.6.
  final double speed;

  /// Playback gain, 0–1.
  final double volume;

  /// When false the companion stays silent even if the service is reachable.
  final bool enabled;

  /// Whether every finished reply is spoken without being asked.
  final bool autoSpeak;

  bool get isConfigured => enabled && baseUrl.trim().isNotEmpty;

  TtsConfig copyWith({
    String? baseUrl,
    String? voice,
    double? speed,
    double? volume,
    bool? enabled,
    bool? autoSpeak,
  }) {
    return TtsConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      enabled: enabled ?? this.enabled,
      autoSpeak: autoSpeak ?? this.autoSpeak,
    );
  }

  @override
  String toString() =>
      'TtsConfig(baseUrl: $baseUrl, voice: $voice, speed: $speed, '
      'volume: $volume, enabled: $enabled, autoSpeak: $autoSpeak)';
}

/// Reads and writes [TtsConfig] through the settings table.
class TtsConfigStore {
  TtsConfigStore(this._settings);

  final SettingsRepository _settings;

  Future<TtsConfig> load() async {
    const fallback = TtsConfig.defaults;
    return TtsConfig(
      baseUrl: _nonEmpty(await _settings.get(TtsConfig.baseUrlKey)) ??
          fallback.baseUrl,
      voice: _nonEmpty(await _settings.get(TtsConfig.voiceKey)) ??
          fallback.voice,
      speed: _parseDouble(
            await _settings.get(TtsConfig.speedKey),
            min: 0.6,
            max: 1.6,
          ) ??
          fallback.speed,
      volume: _parseDouble(
            await _settings.get(TtsConfig.volumeKey),
            min: 0,
            max: 1,
          ) ??
          fallback.volume,
      enabled: _parseBool(await _settings.get(TtsConfig.enabledKey)) ??
          fallback.enabled,
      autoSpeak: _parseBool(await _settings.get(TtsConfig.autoSpeakKey)) ??
          fallback.autoSpeak,
    );
  }

  Future<void> save(TtsConfig config) async {
    await _settings.set(TtsConfig.baseUrlKey, config.baseUrl.trim());
    await _settings.set(TtsConfig.voiceKey, config.voice);
    await _settings.set(TtsConfig.speedKey, '${config.speed}');
    await _settings.set(TtsConfig.volumeKey, '${config.volume}');
    await _settings.set(TtsConfig.enabledKey, '${config.enabled}');
    await _settings.set(TtsConfig.autoSpeakKey, '${config.autoSpeak}');
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  double? _parseDouble(String? value, {required double min, required double max}) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < min || parsed > max) return null;
    return parsed;
  }

  bool? _parseBool(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
    }
    return null;
  }
}
