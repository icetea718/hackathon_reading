import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/assistant/assistant_service.dart';
import 'package:coread/assistant/persona.dart';
import 'package:coread/assistant/reading_context.dart';
import 'package:coread/features/companion/companion_greeting.dart';

class _FakeAssistant implements AssistantService {
  _FakeAssistant(this.chunks, {this.configured = true});

  final List<String> chunks;
  final bool configured;
  String? lastPrompt;
  PersonaMode? lastPersona;

  @override
  bool get isConfigured => configured;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    lastPrompt = userMessage;
    lastPersona = persona;
    return Stream.fromIterable(chunks);
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) =>
      const Stream.empty();

  @override
  Stream<String> summarizeChapter(ReadingContext context) =>
      const Stream.empty();

  @override
  Stream<String> translate(String text, {required String targetLang}) =>
      const Stream.empty();
}

class _ThrowingAssistant implements AssistantService {
  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) => Stream<String>.error(StateError('upstream down'));

  @override
  Stream<String> explain(String text, {required ReadingContext context}) =>
      const Stream.empty();

  @override
  Stream<String> summarizeChapter(ReadingContext context) =>
      const Stream.empty();

  @override
  Stream<String> translate(String text, {required String targetLang}) =>
      const Stream.empty();
}

/// Answers with the default voice without touching the settings database.
class _StubPersona extends PersonaModeNotifier {
  @override
  PersonaMode build() => PersonaMode.fallback;
}

/// A reader who switched to the argumentative voice.
class _DebatePersona extends PersonaModeNotifier {
  @override
  PersonaMode build() => PersonaMode.debate;
}

/// Settings table that remembers the argumentative voice.
class _StoredDebate implements PersonaModeStore {
  @override
  Future<PersonaMode> load() async => PersonaMode.debate;

  @override
  Future<void> save(PersonaMode mode) async {}
}

const _request = CompanionGreetingRequest(
  bookId: 'b1',
  chapterIndex: 0,
  chapterTitle: '第一章',
  chapterText: '母亲给我讲过几十个关于她童年的故事。',
  pageText: '母亲给我讲过几十个关于她童年的故事。',
  readerOffset: 0,
  bookTitle: '你当像鸟飞往你的山',
  author: '塔拉',
);

void main() {
  group('condenseGreeting', () {
    test('keeps the first sentence only', () {
      expect(
        condenseGreeting('这一页的鞋跟真低呀。后面还有别的。'),
        '这一页的鞋跟真低呀。',
      );
    });

    test('strips quotes and speaker prefixes', () {
      expect(condenseGreeting('陪读： “你也在想那双奶油色鞋子吗？”'),
          '你也在想那双奶油色鞋子吗？');
    });

    test('caps long answers', () {
      final line = condenseGreeting('啊' * 200);
      expect(line!.length, lessThanOrEqualTo(companionGreetingMaxLength + 1));
    });

    test('returns null for blank answers', () {
      expect(condenseGreeting('   \n '), isNull);
      expect(condenseGreeting('“”'), isNull);
    });
  });

  group('companionGreeterProvider', () {
    test('asks the assistant and keeps one line', () async {
      final assistant = _FakeAssistant(['这位妈妈', '在挑鞋呢。', '还有后文']);
      final container = ProviderContainer(
        overrides: [
          personaModeProvider.overrideWith(_StubPersona.new),
          assistantServiceProvider.overrideWith((ref) async => assistant),
        ],
      );
      addTearDown(container.dispose);

      final line = await container.read(companionGreeterProvider)(_request);

      expect(line, '这位妈妈在挑鞋呢。');
      expect(assistant.lastPrompt, contains('你当像鸟飞往你的山'));
      expect(assistant.lastPrompt, contains('第一章'));
      expect(assistant.lastPrompt, contains('母亲给我讲过'));
    });

    test('opens with the temper of the chosen voice', () async {
      final assistant = _FakeAssistant(['冷漠是结论。']);
      final container = ProviderContainer(
        overrides: [
          personaModeProvider.overrideWith(_DebatePersona.new),
          assistantServiceProvider.overrideWith((ref) async => assistant),
        ],
      );
      addTearDown(container.dispose);

      await container.read(companionGreeterProvider)(_request);

      expect(assistant.lastPersona, PersonaMode.debate);
      expect(assistant.lastPrompt, contains('不太同意'));
      expect(assistant.lastPrompt, isNot(contains('小细节')));
      expect(assistant.lastPrompt, contains('思辨讨论'));
      expect(assistant.lastPrompt, contains(PersonaMode.debate.sample));
      expect(assistant.lastPrompt, contains(PersonaMode.debate.blurb));
    });

    test('names the gentle voice in the prompt', () async {
      final assistant = _FakeAssistant(['这双鞋挺合脚的。']);
      final container = ProviderContainer(
        overrides: [
          personaModeProvider.overrideWith(_StubPersona.new),
          assistantServiceProvider.overrideWith((ref) async => assistant),
        ],
      );
      addTearDown(container.dispose);

      await container.read(companionGreeterProvider)(_request);

      expect(assistant.lastPersona, PersonaMode.gentle);
      expect(assistant.lastPrompt, contains('温柔陪读'));
      expect(assistant.lastPrompt, contains(PersonaMode.gentle.sample));
    });

    test('waits for the stored voice before it speaks', () async {
      final assistant = _FakeAssistant(['这条你未必同意。']);
      final container = ProviderContainer(
        overrides: [
          personaModeStoreProvider.overrideWithValue(_StoredDebate()),
          assistantServiceProvider.overrideWith((ref) async => assistant),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(personaModeProvider.notifier)
          .ensureRestored()
          .timeout(const Duration(seconds: 2));

      expect(container.read(personaModeProvider), PersonaMode.debate);

      await container.read(companionGreeterProvider)(_request);

      expect(assistant.lastPersona, PersonaMode.debate);
      expect(assistant.lastPrompt, contains('思辨讨论'));
    });

    test('stays silent when no AI service is configured', () async {
      final assistant = _FakeAssistant(['不该出现'], configured: false);
      final container = ProviderContainer(
        overrides: [
          personaModeProvider.overrideWith(_StubPersona.new),
          assistantServiceProvider.overrideWith((ref) async => assistant),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(companionGreeterProvider)(_request), isNull);
    });

    test('stays silent when the assistant stream fails', () async {
      final container = ProviderContainer(
        overrides: [
          personaModeProvider.overrideWith(_StubPersona.new),
          assistantServiceProvider.overrideWith(
            (ref) async => _ThrowingAssistant(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(companionGreeterProvider)(_request), isNull);
    });
  });
}
