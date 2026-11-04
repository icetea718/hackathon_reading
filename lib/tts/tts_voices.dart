import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'edge/edge_voices.dart';

/// One entry of the voice list the settings page shows.
class TtsVoice {
  const TtsVoice({
    required this.id,
    required this.label,
    required this.builtIn,
  });

  /// The name stored in `tts.voice` and sent to whichever engine speaks.
  final String id;

  /// What the user reads.
  final String label;

  /// True when the app speaks it itself over the online endpoint; false when it
  /// needs a local chino-tts with the matching reference audio.
  final bool builtIn;
}

/// The one voice list both engines feed.
///
/// Before this, the app offered `zhino / zhino-clone / xiaoyi / xiaoxiao / xll /
/// dfy` while the service offered `zhino / zhino-quiet / xiaoyi / xiaoxiao /
/// zhino-clone / xiaoyu / luxun` — two of the app's names did not exist (the
/// service silently substituted its default) and three of the service's did not
/// appear in the app. Now the local catalog is authoritative and
/// `GET {service}/voices` only adds what the service itself knows.
class TtsVoices {
  const TtsVoices._();

  /// Voices the app always has; no server, no model.
  static List<TtsVoice> get builtIn => <TtsVoice>[
        for (final voice in EdgeVoices.all)
          TtsVoice(id: voice.id, label: voice.label, builtIn: true),
      ];

  /// Clone voices a stock chino-tts ships. Listed even when the service is
  /// down, so a saved voice never disappears from the picker.
  static const List<TtsVoice> serviceOnly = <TtsVoice>[
    TtsVoice(id: 'zhino-clone', label: '智乃 · 克隆（需本机服务）', builtIn: false),
    TtsVoice(id: 'xiaoyu', label: '小语 · 克隆（需本机服务）', builtIn: false),
    TtsVoice(id: 'luxun', label: '鲁迅 · F5 克隆（需本机服务）', builtIn: false),
  ];

  /// What the picker shows when the service cannot be reached.
  static List<TtsVoice> get fallback => <TtsVoice>[
        ...builtIn,
        ...serviceOnly,
      ];

  /// Whether the app can speak [id] without any local service.
  static bool isBuiltIn(String id) => EdgeVoices.isBuiltIn(id);

  /// Label for [id], even if it is not in any list.
  static String labelOf(String id) {
    for (final voice in <TtsVoice>[...builtIn, ...serviceOnly]) {
      if (voice.id == id) return voice.label;
    }
    return id;
  }

  /// Reads `GET {base}/voices` and merges it with the local catalog.
  ///
  /// Any failure falls back to the static list: the picker must not go empty
  /// just because the user has no local service running.
  static Future<List<TtsVoice>> load(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final root = _root(baseUrl);
    if (root.isEmpty) return fallback;

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse('$root/voices'));
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return fallback;
      final body = await utf8.decodeStream(response).timeout(timeout);
      final decoded = jsonDecode(body);
      final profiles = decoded is Map ? decoded['profiles'] : null;
      if (profiles is! Map) return fallback;

      final served = <TtsVoice>[];
      final seen = <String>{};
      for (final entry in profiles.entries) {
        final id = entry.key.toString();
        if (id.isEmpty) continue;
        final value = entry.value;
        final label = value is Map && value['label'] is String
            ? value['label'] as String
            : null;
        served.add(
          TtsVoice(
            id: id,
            label: label ?? labelOf(id),
            builtIn: EdgeVoices.isBuiltIn(id),
          ),
        );
        seen.add(id);
      }
      // A service that lists its own subset must not hide a voice the app can
      // always speak.
      for (final voice in builtIn) {
        if (!seen.contains(voice.id)) served.add(voice);
      }
      served.sort((a, b) {
        if (a.builtIn == b.builtIn) return 0;
        return a.builtIn ? -1 : 1;
      });
      return served;
    } on Object {
      return fallback;
    } finally {
      client.close(force: true);
    }
  }

  /// Accepts `127.0.0.1:8766`, `http://host:port/`, `http://host:port/v1`.
  static String _root(String baseUrl) {
    var root = baseUrl.trim();
    if (root.isEmpty) return '';
    if (!root.contains('://')) root = 'http://$root';
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    for (final suffix in const <String>[
      '/v1/audio/speech',
      '/audio/speech',
      '/v1',
    ]) {
      if (root.toLowerCase().endsWith(suffix)) {
        root = root.substring(0, root.length - suffix.length);
        break;
      }
    }
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    return root;
  }
}
