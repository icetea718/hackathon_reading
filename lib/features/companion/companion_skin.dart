import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../data/repositories/settings_repository.dart';
import 'companion_clip.dart';

/// What the reader just did to the companion; picks the clip to play.
enum CompanionAction { idle, tap, drag, surprise, wave }

/// One look for the companion: a label, and the clips that play for it.
///
/// A skin does not have to ship every motion. Missing actions fall back to the
/// idle loop, and the spring body still squashes the character on a poke, so a
/// single-motion skin stays interactive.
@immutable
class CompanionSkin {
  const CompanionSkin({
    required this.id,
    required this.label,
    required this.clips,
  });

  final String id;
  final String label;
  final Map<CompanionAction, CompanionClip> clips;

  CompanionClip get idleClip => clips[CompanionAction.idle]!;

  CompanionClip clipFor(CompanionAction action) =>
      clips[action] ?? idleClip;
}

/// The character that has been sitting beside the page since slice four.
const CompanionSkin companionDonutSkin = CompanionSkin(
  id: 'donut',
  label: '甜甜圈女孩',
  clips: <CompanionAction, CompanionClip>{
    CompanionAction.idle: companionIdleClip,
    CompanionAction.tap: companionPokeClip,
    CompanionAction.drag: companionDragClip,
    CompanionAction.surprise: companionSurpriseClip,
    CompanionAction.wave: companionWaveClip,
  },
);

/// Imported art: 25 frames of 512x512, 80ms each, packed 5 per row.
const CompanionClip companionWriterIdleClip = CompanionClip(
  asset: 'assets/companion/luxun_idle.png',
  frameCount: 25,
  fps: 12.5,
  loop: true,
  columns: 5,
  cell: Size(150, 200),
);

/// A reader-supplied look with a single idle motion.
const CompanionSkin companionWriterSkin = CompanionSkin(
  id: 'writer',
  label: '鲁迅',
  clips: <CompanionAction, CompanionClip>{
    CompanionAction.idle: companionWriterIdleClip,
  },
);

/// Everything the reader can pick from, in the order the picker shows them.
const List<CompanionSkin> companionSkins = <CompanionSkin>[
  companionDonutSkin,
  companionWriterSkin,
];

const CompanionSkin companionDefaultSkin = companionDonutSkin;

/// Stored ids are translated back to a known skin; unknown values keep the
/// default so a downgrade never leaves the reader without a companion.
CompanionSkin companionSkinById(String? id) {
  for (final skin in companionSkins) {
    if (skin.id == id) return skin;
  }
  return companionDefaultSkin;
}

class CompanionSkinStore {
  CompanionSkinStore(this._settings);

  final SettingsRepository _settings;

  static const key = 'companion.skin';

  Future<CompanionSkin> load() async => companionSkinById(await _settings.get(key));

  Future<void> save(CompanionSkin skin) async {
    await _settings.set(key, skin.id);
  }
}
