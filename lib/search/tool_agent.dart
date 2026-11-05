import 'dart:async';
import 'dart:convert';

import '../distill/llm/llm_client.dart';
import 'agent_service.dart';
import 'book_context.dart';
import 'book_memory.dart';
import 'book_toolbox.dart';
import 'search_hit.dart';
import 'search_step.dart';

typedef TextSink = void Function(String delta);
typedef StepSink = void Function(SearchStep step);

/// Appended to the 搜 system prompt when the book tools are available.
const String searchToolRules = '''
这本书可以用工具查：先看上面的蒸馏内容判断答案大概落在哪几章，需要原文证据时调 search_in_book；
想确认上下文或核对引文时调 get_chapter。返回的片段带章号与字符偏移。
引用原文写成 Markdown 引用块（> 开头），后面标注「（第 N 章）」。
不要为了「多查一点」反复检索同一个点；蒸馏和检索都找不到时，就说这本书里没有写到。''';

const String searchStepLimitNotice = '已达到检索上限，请基于已有材料作答。';
const String searchDeadlineNotice = '已耗时过长，请基于已有材料作答。';

class ToolRunResult {
  const ToolRunResult({required this.steps, required this.toolCalls});

  final List<SearchStep> steps;

  /// How many tool calls actually ran (skipped ones do not count).
  final int toolCalls;
}

/// Thrown when the endpoint looks like it does not accept `tools`.
class ToolUnsupportedException implements Exception {
  const ToolUnsupportedException(this.cause);

  final Object cause;

  @override
  String toString() => 'ToolUnsupportedException: $cause';
}

/// Runs the ReAct loop over the book tools, then streams the final answer.
///
/// Stateless: the caller builds one [BookToolbox] per question and passes it to
/// [run], so a single instance serves every book.
class SearchToolAgent {
  SearchToolAgent({
    required this.client,
    this.temperature = 0.7,
    this.maxTokens = 2000,
    this.maxSteps = 4,
    this.maxToolChars = 6000,
    this.decisionMaxTokens = 500,
    this.deadline = const Duration(seconds: 90),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LlmClient client;
  final double temperature;
  final int? maxTokens;

  /// Tool calls allowed in one question, across all decision turns.
  final int maxSteps;

  /// Characters of tool output allowed in total.
  final int maxToolChars;

  /// Budget for one decision turn; these replies are short by nature.
  final int decisionMaxTokens;

  /// Wall-clock budget for the whole loop, ending in a closing turn.
  final Duration deadline;

  /// Below this much remaining budget a call is skipped rather than executed:
  /// a result squeezed into a few dozen characters is not worth the round trip.
  static const int minRoomForCall = 200;

  final DateTime Function() _now;

  Future<ToolRunResult> run({
    required List<LlmMessage> history,
    required String userText,
    required BookContext book,
    required BookToolbox toolbox,
    BookMemory? memory,
    List<SearchHit> hits = const [],
    required CancelToken cancel,
    required TextSink onText,
    required StepSink onStep,
  }) async {
    final steps = <SearchStep>[];
    if (cancel.isCanceled) {
      return const ToolRunResult(steps: [], toolCalls: 0);
    }

    final deadlineAt = _now().add(deadline);
    final messages = SearchAgentService(client: client).buildMessages(
      history: history,
      userText: userText,
      hits: hits,
      book: book,
      memory: memory,
    );
    // The toolbox rides on the system message so book/memory formatting stays
    // in one place (SearchAgentService).
    messages[0] = LlmMessage(
      LlmRole.system,
      '${messages[0].content}\n\n$searchToolRules',
    );

    final seenArguments = <String>{};
    var budget = 0;
    var executed = 0;
    String? haltNotice;

    while (true) {
      if (cancel.isCanceled) {
        return ToolRunResult(steps: steps, toolCalls: executed);
      }
      if (_now().isAfter(deadlineAt)) {
        haltNotice = searchDeadlineNotice;
        break;
      }

      final LlmTurn turn;
      try {
        turn = await client.completeTurn(
          messages,
          tools: BookToolbox.specs,
          temperature: temperature,
          maxTokens: decisionMaxTokens,
          cancel: cancel,
        );
      } on LlmException catch (error) {
        if (_looksUnsupported(error)) throw ToolUnsupportedException(error);
        rethrow;
      }

      if (!turn.wantsTools) {
        // Keep the answer the model just gave as the opening of its own reply,
        // so the closing stream continues it instead of starting over.
        if (turn.content.trim().isNotEmpty) {
          messages.add(LlmMessage(LlmRole.assistant, turn.content));
          onText(turn.content);
        }
        break;
      }

      messages.add(
        LlmMessage(LlmRole.assistant, turn.content, toolCalls: turn.toolCalls),
      );

      var anyExecuted = false;
      for (final call in turn.toolCalls) {
        final startedAt = _now();
        final key = _keyOf(call);
        String payload;

        if (executed >= maxSteps) {
          payload = _skipped('step_limit');
        } else if (seenArguments.contains(key)) {
          payload = _skipped('duplicate');
        } else if (maxToolChars - budget < minRoomForCall) {
          payload = _skipped('budget');
        } else {
          seenArguments.add(key);
          executed++;
          anyExecuted = true;
          try {
            payload = await toolbox.call(call.name, call.arguments);
          } catch (error) {
            payload = jsonEncode({'error': '工具执行失败：$error'});
          }
          // The cap bounds how much the next decision request carries, so a
          // single oversized answer is fitted to the room that is left instead
          // of overshooting it.
          payload = _fitPayload(payload, maxToolChars - budget);
          budget += payload.length;
          onStep(_stepOf(call, payload, startedAt));
        }

        // Protocol rule: every call id gets an answer, skipped or not.
        messages.add(
          LlmMessage(LlmRole.tool, payload, toolCallId: call.id),
        );

        if (cancel.isCanceled) {
          return ToolRunResult(steps: steps, toolCalls: executed);
        }
      }

      if (!anyExecuted) {
        haltNotice = searchStepLimitNotice;
        break;
      }
    }

    if (cancel.isCanceled) {
      return ToolRunResult(steps: steps, toolCalls: executed);
    }
    if (haltNotice != null) {
      messages.add(LlmMessage(LlmRole.user, haltNotice));
    }
    await for (final delta in client.streamChat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      cancel: cancel,
    )) {
      onText(delta);
    }

    return ToolRunResult(steps: steps, toolCalls: executed);
  }

  /// Only the shapes an endpoint uses to say "I don't take `tools`": a bad
  /// request, an unknown field, an unusable payload, or a server that chokes on
  /// it. Anything else (429, 503, 401) is a transient or auth problem and must
  /// not be remembered as "this model cannot do tools".
  static const Set<int> unsupportedStatuses = {400, 404, 422, 500};

  static bool _looksUnsupported(LlmException error) {
    final status = error.statusCode ?? 0;
    if (!unsupportedStatuses.contains(status)) return false;
    final message = error.message.toLowerCase();
    return message.contains('tool') || message.contains('function');
  }

  static String _keyOf(LlmToolCall call) =>
      '${call.name}|${call.arguments.trim()}';

  static String _skipped(String reason) =>
      jsonEncode({'error': 'skipped: $reason'});

  /// Fits [payload] into [room] characters without breaking the JSON the model
  /// has to parse: hits are dropped from the end first, then the longest `text`
  /// field is halved until it fits. Only when nothing survives is the answer
  /// replaced by an error the model can react to.
  static String _fitPayload(String payload, int room) {
    if (payload.length <= room) return payload;

    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      return jsonEncode({
        'error': 'budget',
        'note': '这次结果超出字数预算，已丢弃；请缩小范围再查',
      });
    }

    final copy = Map<String, Object?>.from(decoded);
    final hits = copy['hits'];
    if (hits is List) {
      final kept = List<Object?>.from(hits);
      while (kept.isNotEmpty &&
          jsonEncode({...copy, 'hits': kept}).length > room) {
        kept.removeLast();
      }
      if (kept.length != hits.length) {
        copy['hits'] = kept;
        copy['truncated'] = true;
      }
    }

    var encoded = jsonEncode(copy);
    if (encoded.length > room) {
      Map<Object?, Object?>? holder;
      if (copy['text'] is String) {
        holder = copy;
      } else if (copy['hits'] is List && (copy['hits'] as List).isNotEmpty) {
        final first = (copy['hits'] as List).first;
        if (first is Map && first['text'] is String) holder = first;
      }
      if (holder != null && holder['text'] is String) {
        final original = holder['text']! as String;
        var keep = original.length;
        while (keep > 0) {
          keep = keep ~/ 2;
          holder['text'] = keep == 0 ? '' : '${original.substring(0, keep)}…';
          encoded = jsonEncode(copy);
          if (encoded.length <= room) break;
        }
      }
    }

    if (encoded.length <= room) return encoded;
    return jsonEncode({
      'error': 'budget',
      'note': '这次结果超出字数预算，已丢弃；请缩小范围再查',
    });
  }

  /// Every executed call leaves a trace, failed ones included: a reader who
  /// watched "检索「雨」" appear should not see it vanish because the tool
  /// answered with an error. Only skipped calls stay invisible.
  SearchStep _stepOf(LlmToolCall call, String payload, DateTime startedAt) {
    final rawMs = _now().difference(startedAt).inMilliseconds;
    final ms = rawMs < 0 ? 0 : rawMs;

    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      decoded = null;
    }
    final map = decoded is Map ? decoded : const <String, Object?>{};
    final failed = decoded is! Map || map.containsKey('error');

    if (call.name == 'get_chapter') {
      final chapter = map['chapter'] ?? _chapterOf(call.arguments);
      final label = chapter is int ? '第 $chapter 章' : '这一章';
      return SearchStep(
        tool: call.name,
        summary: failed ? '读$label失败' : '读$label',
        chapters: [if (chapter is int) chapter],
        hits: 0,
        ms: ms,
      );
    }

    final query = _queryOf(call.arguments);
    if (failed) {
      return SearchStep(
        tool: call.name,
        summary: query.isEmpty ? '检索原文失败' : '检索「$query」失败',
        chapters: const [],
        hits: 0,
        ms: ms,
      );
    }

    final hits = map['hits'];
    final chapters = <int>{};
    var count = 0;
    if (hits is List) {
      count = hits.length;
      for (final hit in hits) {
        if (hit is Map && hit['chapter'] is int) chapters.add(hit['chapter'] as int);
      }
    }
    return SearchStep(
      tool: call.name,
      summary: query.isEmpty ? '检索原文' : '检索「$query」',
      chapters: chapters.toList()..sort(),
      hits: count,
      ms: ms,
    );
  }

  static int? _chapterOf(String arguments) {
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) {
        final chapter = decoded['chapter'];
        if (chapter is int) return chapter;
      }
    } on FormatException {
      // Malformed arguments: the tool call already reported the error.
    }
    return null;
  }

  static String _queryOf(String arguments) {
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) {
        final query = decoded['query'];
        if (query is String) return query.trim();
      }
    } on FormatException {
      // Malformed arguments: the tool call already reported the error.
    }
    return '';
  }
}
