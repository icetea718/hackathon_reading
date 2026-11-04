import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/assistant/persona.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/settings_repository.dart';

void main() {
  group('PersonaMode', () {
    test('defaults to the gentle voice', () {
      expect(PersonaMode.fallback, PersonaMode.gentle);
    });

    test('reads a stored id back, and falls back on junk', () {
      for (final mode in PersonaMode.values) {
        expect(PersonaMode.fromId(mode.id), mode);
      }
      expect(PersonaMode.fromId(null), PersonaMode.gentle);
      expect(PersonaMode.fromId(''), PersonaMode.gentle);
      expect(PersonaMode.fromId('shouty'), PersonaMode.gentle);
    });

    test('ids are unique and stable', () {
      final ids = PersonaMode.values.map((mode) => mode.id).toList();
      expect(ids, ['gentle', 'debate']);
    });

    test('each mode has its own temper on top of a shared engine', () {
      final gentle = PersonaMode.gentle.systemPrompt;
      final debate = PersonaMode.debate.systemPrompt;

      expect(gentle, contains('当前模式：温柔陪读'));
      expect(gentle, isNot(contains('当前模式：思辨讨论')));
      expect(debate, contains('当前模式：思辨讨论'));
      expect(debate, isNot(contains('当前模式：温柔陪读')));

      // Same person, different temper: the shared rules appear verbatim in both.
      for (final rule in [
        '总共不超过 60 字',
        '先回应他上一句',
        '不代读',
        '永远不说"作为陪读 AI"',
      ]) {
        expect(gentle, contains(rule), reason: rule);
        expect(debate, contains(rule), reason: rule);
      }
    });

    test('the shared rules stay short enough to keep replies short', () {
      // A bloated prompt is the usual reason a companion starts lecturing.
      expect(PersonaMode.gentle.systemPrompt.length, lessThan(1200));
      expect(PersonaMode.debate.systemPrompt.length, lessThan(1200));
    });

    test('every mode shows the reader something to choose by', () {
      for (final mode in PersonaMode.values) {
        expect(mode.label, isNotEmpty);
        expect(mode.shortLabel.length, lessThanOrEqualTo(3));
        expect(mode.blurb, isNotEmpty);
        expect(mode.sample, isNotEmpty);
        expect(mode.composerHint, isNotEmpty);
        expect(mode.greetingHint, isNotEmpty);
      }
      expect(
        PersonaMode.values.map((mode) => mode.label).toSet().length,
        PersonaMode.values.length,
      );
    });
  });

  group('PersonaModeStore', () {
    late AppDatabase db;
    late PersonaModeStore store;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = PersonaModeStore(SettingsRepository(db));
    });
    tearDown(() => db.close());

    test('starts from the default voice', () async {
      expect(await store.load(), PersonaMode.gentle);
    });

    test('remembers the reader choice across reads', () async {
      await store.save(PersonaMode.debate);
      expect(await store.load(), PersonaMode.debate);

      await store.save(PersonaMode.gentle);
      expect(await store.load(), PersonaMode.gentle);
    });

    test('stores under a stable key so old installs keep working', () {
      expect(PersonaModeStore.key, 'companion.persona');
    });
  });
}
