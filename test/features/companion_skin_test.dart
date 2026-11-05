import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/repositories/settings_repository.dart';
import 'package:coread/features/companion/companion_clip.dart';
import 'package:coread/features/companion/companion_skin.dart';

class _MemorySettings implements SettingsRepository {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  group('catalog', () {
    test('ships two skins with unique ids and a default to sit on', () {
      expect(companionSkins, hasLength(2));
      expect(
        companionSkins.map((skin) => skin.id).toSet(),
        hasLength(companionSkins.length),
      );
      for (final skin in companionSkins) {
        expect(skin.label, isNotEmpty);
        expect(skin.idleClip.frameCount, greaterThan(0));
        expect(skin.idleClip.loop, isTrue);
      }
      expect(companionDefaultSkin, companionDonutSkin);
    });

    test('the imported skin stands still until the reader touches it', () {
      final idle = companionWriterSkin.idleClip;
      expect(idle.asset, 'assets/companion/luxun_idle.png');
      expect(idle.frameCount, 1);
      expect(idle.columns, 5);
      expect(idle.cell, const Size(150, 200));

      // The supplied pack is the reaction, not the idle: poking him, turning
      // the page and the bubble popping all play it.
      for (final action in const [
        CompanionAction.tap,
        CompanionAction.surprise,
        CompanionAction.wave,
      ]) {
        expect(companionWriterSkin.clipFor(action), companionWriterActionClip);
      }

      // Dragging is answered by the spring body, so he keeps the standing pose.
      expect(companionWriterSkin.clipFor(CompanionAction.drag), idle);
      expect(companionWriterActionClip.frameCount, 25);
    });

    test('the donut skin keeps every reaction it was baked with', () {
      expect(
        companionDonutSkin.clipFor(CompanionAction.tap),
        companionPokeClip,
      );
      expect(
        companionDonutSkin.clipFor(CompanionAction.drag),
        companionDragClip,
      );
      expect(
        companionDonutSkin.clipFor(CompanionAction.surprise),
        companionSurpriseClip,
      );
      expect(
        companionDonutSkin.clipFor(CompanionAction.wave),
        companionWaveClip,
      );
    });

    test('unknown ids fall back to the default skin', () {
      expect(companionSkinById('writer'), companionWriterSkin);
      expect(companionSkinById('nope'), companionDefaultSkin);
      expect(companionSkinById(null), companionDefaultSkin);
    });
  });

  group('store', () {
    test('saves the id and reads it back', () async {
      final settings = _MemorySettings();
      final store = CompanionSkinStore(settings);

      await store.save(companionWriterSkin);
      expect(settings.values[CompanionSkinStore.key], 'writer');
      expect(await store.load(), companionWriterSkin);
    });

    test('an empty setting means the default skin', () async {
      final store = CompanionSkinStore(_MemorySettings());
      expect(await store.load(), companionDefaultSkin);
    });
  });
}
