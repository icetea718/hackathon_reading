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
        if (turn.content.trim().isNotEmpty) onText(turn.content);
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
        } else if (budget >= maxToolChars) {
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
          budget += payload.length;
          final step = _stepOf(call, payload, startedAt);
          if (step != null) onStep(step);
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

  static bool _looksUnsupported(LlmException error) {
    final status = error.statusCode ?? 0;
    if (status < 400) return false;
    final message = error.message.toLowerCase();
    return message.contains('tool') || message.contains('function');
  }

  static String _keyOf(LlmToolCall call) =>
      '${call.name}|${call.arguments.trim()}';

  static String _skipped(String reason) =>
      jsonEncode({'error': 'skipped: $reason'});

  SearchStep? _stepOf(LlmToolCall call, String payload, DateTime startedAt) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map || decoded.containsKey('error')) return null;

    final ms = _now().difference(startedAt).inMilliseconds;

    if (call.name == 'get_chapter') {
      final chapter = decoded['chapter'];
      return SearchStep(
        tool: call.name,
        summary: '读第 $chapter 章',
        chapters: [if (chapter is int) chapter],
        hits: 0,
        ms: ms < 0 ? 0 : ms,
      );
    }

    final hits = decoded['hits'];
    final chapters = <int>{};
    var count = 0;
    if (hits is List) {
      count = hits.length;
      for (final hit in hits) {
        if (hit is Map && hit['chapter'] is int) chapters.add(hit['chapter'] as int);
      }
    }
    final query = _queryOf(call.arguments);
    return SearchStep(
      tool: call.name,
      summary: query.isEmpty ? '检索原文' : '检索「$query」',
      chapters: chapters.toList()..sort(),
      hits: count,
      ms: ms < 0 ? 0 : ms,
    );
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
