import 'dart:async';

import '../distill/llm/llm_client.dart';
import 'search_hit.dart';

/// Persona for the 搜 shell: a general assistant that may or may not have web
/// results in front of it.
const String searchSystemPrompt = '''
你是一个中文智能助手，回答直接、具体、有条理。
用 Markdown 组织答案：需要分点时用列表，需要举例时用短代码块或引用。
如果用户的问题涉及最新消息、价格、版本、人物近况等可能变化的事实，而下面没有附上参考资料，就明确说出你的知识可能过时，不要给出笃定的结论。
不要编造链接、数字或引文。''';

/// Candidates are only appended when retrieval actually returned something.
const String searchHitsHeader = '【检索结果】';

/// Builds the message list for the 搜 shell and streams the answer.
class SearchAgentService {
  SearchAgentService({
    required this.client,
    this.temperature = 0.7,
    this.maxTokens = 2000,
  });

  /// How many characters of earlier turns are kept; newest turns win.
  static const int maxHistoryChars = 8000;

  final LlmClient client;
  final double temperature;
  final int? maxTokens;

  Stream<String> send({
    required List<LlmMessage> history,
    required String userText,
    List<SearchHit> hits = const [],
    required CancelToken cancel,
  }) {
    if (cancel.isCanceled) return const Stream<String>.empty();

    final messages = buildMessages(
      history: history,
      userText: userText,
      hits: hits,
    );
    return client.streamChat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      cancel: cancel,
    );
  }

  /// System prompt + as much history as fits + the current question.
  List<LlmMessage> buildMessages({
    required List<LlmMessage> history,
    required String userText,
    List<SearchHit> hits = const [],
  }) {
    final system = StringBuffer(searchSystemPrompt);
    if (hits.isNotEmpty) {
      system
        ..write('\n\n')
        ..write(searchHitsHeader)
        ..write('\n')
        ..write(_formatHits(hits))
        ..write('\n引用与答案相关的结果时，把来源写成 Markdown 链接。');
    }

    return [
      LlmMessage(LlmRole.system, system.toString()),
      ..._trimHistory(history),
      LlmMessage(LlmRole.user, userText),
    ];
  }

  static String _formatHits(List<SearchHit> hits) {
    final buffer = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final where = hit.url ?? hit.source;
      buffer.writeln('${i + 1}. ${hit.title} — $where');
      if (hit.snippet.isNotEmpty) buffer.writeln('   ${hit.snippet}');
    }
    return buffer.toString();
  }

  /// Keeps whole turns from the newest end until [maxHistoryChars] is reached.
  static List<LlmMessage> _trimHistory(List<LlmMessage> history) {
    if (history.isEmpty) return const [];

    final kept = <LlmMessage>[];
    var budget = maxHistoryChars;
    for (var i = history.length - 1; i >= 0; i--) {
      final message = history[i];
      // Always keep the newest message so an answer never arrives context-free.
      if (kept.isNotEmpty && message.content.length > budget) break;
      budget -= message.content.length;
      kept.insert(0, message);
    }
    return kept;
  }
}
