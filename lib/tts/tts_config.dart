import '../data/repositories/settings_repository.dart';

/// Where the companion voice comes from and how it should sound.
///
/// Two engines answer to these settings. Built-in voices (see `TtsVoices`) are
/// synthesized by the app itself against the Edge read-aloud endpoint, so they
/// work with nothing installed. Clone voices go to a local speech service that
/// speaks the OpenAI `/audio/speech` shape — `chino-tts` at 127.0.0.1:8766 by
/// default, or GPT-SoVITS `api_v2` — the same shape the reference Coopanion
/// plugin exposes.
class TtsConfig {
  const TtsConfig({
    required this.baseUrl,
    required this.voice,
    required this.speed,
    required this.volume,
    required this.autoSpeak,
    this.enabled = true,
  });

  static const String baseUrlKey = 'tts.baseUrl';
  static const String voiceKey = 'tts.voice';
  static const String speedKey = 'tts.speed';
  static const String volumeKey = 'tts.volume';
  static const String enabledKey = 'tts.enabled';
  static const String autoSpeakKey = 'tts.autoSpeak';

  /// Voice used until the user picks another one.
  ///
  /// It is a built-in online voice, so a fresh install speaks without any local
  /// service; the picker's list lives in `TtsVoices`, which merges this app's
  /// own voices with whatever `chino-tts` reports.
  static const String defaultVoice = 'zhino';

  static const TtsConfig defaults = TtsConfig(
    baseUrl: 'http://127.0.0.1:8766',
    voice: defaultVoice,
    speed: 1,
    volume: 1,
    autoSpeak: false,
    enabled: true,
  );

  final String baseUrl;
  final String voice;

  /// Speaking rate, 0.6–1.6.
  final double speed;

  /// Playback gain, 0–1.
  final double volume;

  /// Whether every finished reply is spoken without being asked.
  ///
  /// This only decides automatic playback; it never silences a tap on a
  /// speaker icon or the companion's own lines. [enabled] is the master mute.
  final bool autoSpeak;

  /// Master mute: when false nothing is spoken at all, including pet lines.
  final bool enabled;

  TtsConfig copyWith({
    String? baseUrl,
    String? voice,
    double? speed,
    double? volume,
    bool? autoSpeak,
    bool? enabled,
  }) {
    return TtsConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      autoSpeak: autoSpeak ?? this.autoSpeak,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() =>
      'TtsConfig(baseUrl: $baseUrl, voice: $voice, speed: $speed, '
      'volume: $volume, autoSpeak: $autoSpeak, enabled: $enabled)';
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
      autoSpeak: _parseBool(await _settings.get(TtsConfig.autoSpeakKey)) ??
          fallback.autoSpeak,
      enabled: _parseBool(await _settings.get(TtsConfig.enabledKey)) ??
          fallback.enabled,
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
