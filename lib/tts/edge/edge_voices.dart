/// The voices the app can synthesize on its own, through the Edge read-aloud
/// endpoint.
///
/// These are the same ids, labels and prosody packs `chino-tts` ships in its
/// `voices.json`, so a user sees one list whichever engine ends up speaking —
/// but the app needs no local server, no node, and no model download to use
/// them. Clone voices (`zhino-clone`, `xiaoyu`, `luxun`) stay on the local
/// service, because they need the reference audio and the 2B model.
class EdgeVoice {
  const EdgeVoice({
    required this.id,
    required this.label,
    required this.voice,
    this.rate = 0,
    this.pitch = 0,
    this.volume = 0,
  });

  /// The id the settings store keeps, e.g. `zhino`.
  final String id;

  /// What the settings page shows.
  final String label;

  /// Azure voice name, e.g. `zh-CN-XiaoyiNeural`.
  final String voice;

  /// Rate offset in percent, added to whatever the speed slider asks for.
  final int rate;

  /// Pitch offset in Hz.
  final int pitch;

  /// Volume offset in percent, added to whatever the volume slider asks for.
  final int volume;

  /// `zh-CN` for `zh-CN-XiaoyiNeural`; SSML wants the locale apart from the
  /// voice name.
  String get locale {
    final parts = voice.split('-');
    return parts.length >= 2 ? '${parts[0]}-${parts[1]}' : 'zh-CN';
  }
}

/// Catalog of the voices this app speaks by itself.
class EdgeVoices {
  const EdgeVoices._();

  /// The id used when the stored voice is unknown or a clone one, so a missing
  /// local service degrades to something audible instead of silence.
  static const String defaultId = 'zhino';

  /// Mirrors `profiles` of chino-tts' `voices.json`, edge entries only.
  static const List<EdgeVoice> all = <EdgeVoice>[
    EdgeVoice(
      id: 'zhino',
      label: '晓伊 · 软糯少女',
      voice: 'zh-CN-XiaoyiNeural',
      rate: -8,
      pitch: 6,
    ),
    EdgeVoice(
      id: 'zhino-quiet',
      label: '晓伊 · 安静冷淡',
      voice: 'zh-CN-XiaoyiNeural',
      rate: -15,
      pitch: -8,
      volume: -4,
    ),
    EdgeVoice(
      id: 'xiaoyi',
      label: '晓伊（原味）',
      voice: 'zh-CN-XiaoyiNeural',
    ),
    EdgeVoice(
      id: 'xiaoxiao',
      label: '晓晓 · 温柔',
      voice: 'zh-CN-XiaoxiaoNeural',
      rate: -5,
    ),
  ];

  /// The catalog entry for [id], or null when the id belongs to another engine.
  static EdgeVoice? byId(String? id) {
    if (id == null) return null;
    for (final voice in all) {
      if (voice.id == id) return voice;
    }
    return null;
  }

  /// [id] when it is an edge voice, otherwise the default one.
  static EdgeVoice resolve(String? id) => byId(id) ?? byId(defaultId)!;

  /// Whether this app can speak [id] without any local service.
  static bool isBuiltIn(String? id) => byId(id) != null;

  /// Labels for the settings page, keyed by id.
  static String labelOf(String id) =>
      byId(id)?.label ?? id;
}
