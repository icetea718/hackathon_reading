import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/persona.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/features/companion/companion_chat_controller.dart';

const _context = ReadingContext(bookTitle: '你当像鸟飞往你的山', chapterTitle: '第一部分');

class _ScriptedAssistant implements AssistantService {
  _ScriptedAssistant(this.turns);

  /// One stream per call, consumed in order.
  final List<Stream<String>> turns;
  final prompts = <String>[];
  int _calls = 0;

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) {
    prompts.add(userMessage);
    final stream = turns[_calls < turns.length ? _calls : turns.length - 1];
    _calls++;
    return stream;
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) =>
      const Stream.empty();

  @override
  Stream<String> summarizeChapter(ReadingContext context) => const Stream.empty();

  @override
  Stream<String> translate(String text, {required String targetLang}) =>
      const Stream.empty();
}

class _UnconfiguredAssistant extends _ScriptedAssistant {
  _UnconfiguredAssistant() : super(const []);

  @override
  bool get isConfigured => false;
}

CompanionChatController _controller(AssistantService service) =>
    CompanionChatController(
      loadService: () async => service,
      loadPersona: () => PersonaMode.fallback,
    );

void main() {
  test('keeps a separate thread per chapter', () async {
    final controller = _controller(
      _ScriptedAssistant([
        Stream.fromIterable(const ['好']),
        Stream.fromIterable(const ['嗯']),
      ]),
    );

    await controller.ask('c1', _context, '第一句');
    await controller.ask('c2', _context, '第二句');

    expect(controller.messagesFor('c1').map((m) => m.content), ['第一句', '好']);
    expect(controller.messagesFor('c2').map((m) => m.content), ['第二句', '嗯']);
  });

  test('exposes the tokens while the answer is still arriving', () async {
    final gate = StreamController<String>();
    final controller = _controller(_ScriptedAssistant([gate.stream]));

    final pending = controller.ask('c1', _context, '问');
    gate.add('桌宠');
    await Future<void>.delayed(Duration.zero);

    expect(controller.busy, isTrue);
    expect(controller.streaming, '桌宠');
    expect(controller.messagesFor('c1').last.content, '问');

    gate.add('回答说');
    await gate.close();
    await pending;

    expect(controller.busy, isFalse);
    expect(controller.streaming, isEmpty);
    expect(controller.messagesFor('c1').last.content, '桌宠回答说');
  });

  test('softens a failed stream into a retry line', () async {
    final controller = _controller(
      _ScriptedAssistant([Stream<String>.error(StateError('upstream down'))]),
    );

    await controller.ask('c1', _context, '问');

    expect(controller.messagesFor('c1').last.content, companionChatFailureLine);
    expect(
      controller.messagesFor('c1').last.role,
      ChatRole.assistant,
    );
    expect(controller.busy, isFalse);
  });

  test('tells the reader when the assistant is not configured', () async {
    final controller = _controller(_UnconfiguredAssistant());

    await controller.ask('c1', _context, '问');

    expect(controller.messagesFor('c1').last.content, companionChatFailureLine);
  });

  test('ignores a second request while one is in flight', () async {
    final gate = StreamController<String>();
    final assistant = _ScriptedAssistant([gate.stream]);
    final controller = _controller(assistant);

    final first = controller.ask('c1', _context, '一');
    await controller.ask('c1', _context, '二');

    expect(assistant.prompts, ['一']);

    gate.add('答');
    await gate.close();
    await first;
    expect(controller.messagesFor('c1').where((m) => m.content == '二'), isEmpty);
  });

  test('keeps the last $companionChatHistoryLimit messages', () async {
    final controller = _controller(
      _ScriptedAssistant([Stream.fromIterable(const ['答'])]),
    );

    for (var i = 0; i < 12; i++) {
      await controller.ask('c1', _context, '问 $i');
    }

    final messages = controller.messagesFor('c1');
    expect(messages.length, companionChatHistoryLimit);
    expect(messages.last.content, '答');
    expect(messages.first.content, '问 2');
  });
}
