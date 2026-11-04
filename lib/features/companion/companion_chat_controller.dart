import 'package:flutter/foundation.dart';

import '../../assistant/assistant_service.dart';
import '../../assistant/persona.dart';
import '../../assistant/reading_context.dart';

/// How many messages a chapter thread keeps before the oldest turn drops.
const companionChatHistoryLimit = 20;

/// Said in the pet's voice when the model is unreachable.
const companionChatFailureLine = '我这会儿有点卡，再问我一次？';

/// Said when no model has been configured yet.
const companionChatOfflineLine = '我还没接上大模型，去设置里填个 key 就能聊了。';

/// Keeps one chat thread per chapter and streams answers into a tail string.
///
/// The reader page owns an instance for the whole page, so closing the bubble
/// panel keeps the conversation; switching chapters switches threads.
class CompanionChatController extends ChangeNotifier {
  CompanionChatController({
    required this.loadService,
    required this.loadPersona,
  });

  final Future<AssistantService> Function() loadService;
  final PersonaMode Function() loadPersona;

  final Map<String, List<ChatMessage>> _sessions = {};
  String _streaming = '';
  bool _busy = false;

  /// Answer tokens of the request in flight, empty when idle.
  String get streaming => _streaming;

  bool get busy => _busy;

  List<ChatMessage> messagesFor(String chapterId) =>
      List.unmodifiable(_sessions[chapterId] ?? const <ChatMessage>[]);

  /// Appends [text] to [chapterId]'s thread and streams the answer in.
  Future<void> ask(
    String chapterId,
    ReadingContext context,
    String text,
  ) async {
    final question = text.trim();
    if (question.isEmpty || _busy) return;

    final thread = _sessions.putIfAbsent(chapterId, () => <ChatMessage>[]);
    final history = List<ChatMessage>.unmodifiable(thread);
    thread.add(ChatMessage(role: ChatRole.user, content: question));

    _busy = true;
    _streaming = '';
    notifyListeners();

    var answer = '';
    try {
      final service = await loadService();
      if (!service.isConfigured) {
        answer = companionChatOfflineLine;
      } else {
        await for (final chunk in service.chat(
          context,
          history,
          question,
          persona: loadPersona(),
        )) {
          answer += chunk;
          _streaming = answer;
          notifyListeners();
        }
      }
    } catch (_) {
      // A half answer still reads better than an error banner.
      if (answer.isEmpty) answer = companionChatFailureLine;
    }

    if (answer.trim().isEmpty) answer = companionChatFailureLine;
    thread.add(ChatMessage(role: ChatRole.assistant, content: answer.trim()));
    _trim(thread);

    _streaming = '';
    _busy = false;
    notifyListeners();
  }

  void _trim(List<ChatMessage> thread) {
    if (thread.length <= companionChatHistoryLimit) return;
    thread.removeRange(0, thread.length - companionChatHistoryLimit);
  }
}
