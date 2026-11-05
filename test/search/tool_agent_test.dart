import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/distill_digest.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/search/book_context.dart';
import 'package:coread/search/book_searcher.dart';
import 'package:coread/search/book_toolbox.dart';
import 'package:coread/search/search_step.dart';
import 'package:coread/search/tool_agent.dart';

class _NoDigest implements DistillDigestSource {
  @override
  Future<DistillDigest?> load(String bookId) async => null;
}

const _book = BookContext(
  bookId: 'b1',
  title: '测试书',
  author: '',
  brief: '这本书记录了很多雨。',
);

const _hitsPayload =
    '{"hits":[{"chapter":3,"title":"第三章","offset":0,"score":9,"text":"雨夜"}]}';

BookToolbox _emptyToolbox() => BookToolbox(
      book: _book,
      searcher: BookSearcher(
        loadChapters: (_) async => const [],
        loadChapterText: (_, _) async => '',
        digests: _NoDigest(),
      ),
    );

class _FakeToolbox extends BookToolbox {
  _FakeToolbox({
    List<String>? payloads,
    this.throwOnCall = false,
  })  : payloads = payloads ?? const [],
        super(book: _book, searcher: _emptyToolbox().searcher);

  final List<String> payloads;
  final bool throwOnCall;
  final List<String> calls = [];

  @override
  Future<String> call(String name, String argumentsJson) async {
    calls.add('$name $argumentsJson');
    if (throwOnCall) throw StateError('boom');
    final index = calls.length - 1;
    if (payloads.isEmpty) return _hitsPayload;
    return payloads[index < payloads.length ? index : payloads.length - 1];
  }
}

class _ScriptedClient extends LlmClient {
  _ScriptedClient(this.turns);

  final List<LlmTurn> turns;
  final List<List<LlmMessage>> seen = [];
  final List<List<LlmToolSpec>?> toolsSent = [];
  String answer = '最终答案';
  Object? throwOnTurn;
  int _index = 0;

  int get turnCalls => toolsSent.whereType<List<LlmToolSpec>>().length;

  @override
  Future<LlmTurn> completeTurn(
    List<LlmMessage> messages, {
    List<LlmToolSpec>? tools,
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async {
    if (throwOnTurn != null) throw throwOnTurn!;
    seen.add(List.of(messages));
    toolsSent.add(tools);
    if (_index >= turns.length) throw StateError('脚本用尽');
    return turns[_index++];
  }

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    seen.add(List.of(messages));
    toolsSent.add(null);
    if (answer.isNotEmpty) yield answer;
  }

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async =>
      '';

  @override
  void dispose() {}
}

Future<void> _run(
  _ScriptedClient client, {
  _FakeToolbox? toolbox,
  List<SearchStep>? steps,
  List<String>? text,
  void Function(SearchStep)? onStep,
  CancelToken? cancel,
  DateTime Function()? now,
  int maxToolChars = 6000,
}) async {
  final sink = steps ?? <SearchStep>[];
  final out = text ?? <String>[];
  await SearchToolAgent(
    client: client,
    now: now,
    maxToolChars: maxToolChars,
  ).run(
    history: const [],
    userText: '这本书里的雨意味着什么？',
    book: _book,
    toolbox: toolbox ?? _FakeToolbox(),
    cancel: cancel ?? CancelToken(),
    onText: out.add,
    onStep: onStep ?? sink.add,
  );
}

const _searchCall = LlmToolCall(
  id: 'call_1',
  name: 'search_in_book',
  arguments: '{"query":"雨"}',
);

void main() {
  test('一轮检索后流式给出答案，tool 消息紧跟 assistant tool_calls', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(),
    ]);
    final steps = <SearchStep>[];
    final text = <String>[];

    await _run(client, steps: steps, text: text);

    final second = client.seen[1].map((m) => m.role).toList();
    expect(second.contains(LlmRole.tool), isTrue);
    expect(
      client.seen[1].lastWhere((m) => m.role == LlmRole.tool).toolCallId,
      'call_1',
    );
    expect(steps.single.chapters, isNotEmpty);
    expect(steps.single.tool, 'search_in_book');
    expect(text.join(), '最终答案');
  });

  test('一个响应带两个 tool_calls → 两个 step、两条 tool 消息', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [
        _searchCall,
        LlmToolCall(id: 'call_2', name: 'get_chapter', arguments: '{"chapter":7}'),
      ]),
      const LlmTurn(),
    ]);
    final steps = <SearchStep>[];

    await _run(
      client,
      steps: steps,
      toolbox: _FakeToolbox(payloads: [
        _hitsPayload,
        '{"chapter":7,"title":"第七章","offset":0,"text":"风起"}',
      ]),
    );

    final toolIds = client.seen[1]
        .where((m) => m.role == LlmRole.tool)
        .map((m) => m.toolCallId)
        .toList();
    expect(toolIds, ['call_1', 'call_2']);
    expect(steps.length, 2);
    expect(steps.last.summary, contains('7'));
  });

  test('达到 4 步上限后发不带 tools 的收尾请求', () async {
    final client = _ScriptedClient([
      for (var i = 0; i < 5; i++)
        LlmTurn(toolCalls: [
          LlmToolCall(id: 'call_$i', name: 'search_in_book', arguments: '{"query":"雨$i"}'),
        ]),
    ]);
    final steps = <SearchStep>[];

    await _run(client, steps: steps);

    expect(steps.length, 4);
    expect(client.toolsSent.last, isNull);
    expect(client.seen.last.last.content, contains('上限'));
  });

  test('相同参数第二次调用不再执行，改为补一条 error 的 tool 消息', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(toolCalls: [
        LlmToolCall(id: 'call_2', name: 'search_in_book', arguments: '{"query":"雨"}'),
      ]),
      const LlmTurn(),
    ]);
    final steps = <SearchStep>[];

    await _run(client, steps: steps);

    expect(steps.length, 1);
    final toolMessage = client.seen.last.lastWhere(
      (m) => m.role == LlmRole.tool,
    );
    expect(toolMessage.role, LlmRole.tool);
    expect(toolMessage.content, contains('skipped'));
  });

  test('工具抛出异常时回 error 的 tool 消息而不是整轮失败', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(),
    ]);
    final text = <String>[];

    await _run(client, toolbox: _FakeToolbox(throwOnCall: true), text: text);

    final toolMessage = client.seen[1].lastWhere((m) => m.role == LlmRole.tool);
    expect(toolMessage.content, contains('error'));
    expect(text.join(), '最终答案');
  });

  test('工具输出累计超过 maxToolChars 后停止喂更多结果', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(toolCalls: [
        LlmToolCall(id: 'call_2', name: 'search_in_book', arguments: '{"query":"风"}'),
      ]),
      const LlmTurn(),
    ]);
    final big = '{"hits":[{"text":"${'雨' * 200}"}]}';

    await _run(
      client,
      toolbox: _FakeToolbox(payloads: [big, big]),
      maxToolChars: 100,
    );

    final toolMessage = client.seen.last.lastWhere(
      (m) => m.role == LlmRole.tool,
    );
    expect(toolMessage.content, contains('skipped'));
  });

  test('cancel 在工具执行前被调用则不再发请求', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
    ]);
    final cancel = CancelToken();

    await _run(client, cancel: cancel, onStep: (_) => cancel.cancel());

    expect(client.seen.length, 1);
  });

  test('超过 deadline 立即走收尾请求（不带 tools）', () async {
    final client = _ScriptedClient(const []);
    final base = DateTime(2026, 1, 5);
    final times = [Duration.zero, const Duration(seconds: 91)];

    await _run(client, now: () => base.add(times.removeAt(0)));

    expect(client.turnCalls, 0);
    expect(client.toolsSent.last, isNull);
    expect(client.seen.single.last.content, contains('耗时'));
  });

  test('首轮就没有 tool_calls 时不产生任何 step，直接流式', () async {
    final client = _ScriptedClient([const LlmTurn(content: '直接答')]);
    final steps = <SearchStep>[];
    final text = <String>[];
    client.answer = '';

    await _run(client, steps: steps, text: text);

    expect(steps, isEmpty);
    expect(client.toolsSent.first, isNotNull);
    expect(text.join(), '直接答');
  });

  test('400 且正文提到 tools 时抛 ToolUnsupportedException', () async {
    final client = _ScriptedClient(const [])
      ..throwOnTurn = LlmException('HTTP 400: unknown field tools', statusCode: 400);

    await expectLater(_run(client), throwsA(isA<ToolUnsupportedException>()));
  });

  test('429 / 503 / 401 不算「端点不支持工具」', () async {
    for (final status in [429, 503, 401]) {
      final client = _ScriptedClient(const [])
        ..throwOnTurn = LlmException('tools are not supported', statusCode: status);

      await expectLater(_run(client), throwsA(isA<LlmException>()));
    }
  });

  test('决策轮直接作答时，答案成为收尾请求里的 assistant 消息', () async {
    final client = _ScriptedClient([const LlmTurn(content: '半句答案')]);
    final text = <String>[];

    await _run(client, text: text);

    final closing = client.seen.last;
    expect(closing.last.role, LlmRole.assistant);
    expect(closing.last.content, '半句答案');
    // 问题只出现一次：答案没有被丢掉重答。
    expect(
      closing.where(
        (m) => m.role == LlmRole.user && m.content.contains('这本书里的雨'),
      ),
      hasLength(1),
    );
    expect(text.join(), startsWith('半句答案'));
  });

  test('工具返回错误时仍留下一步，但标注失败', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(),
    ]);
    final steps = <SearchStep>[];

    await _run(
      client,
      toolbox: _FakeToolbox(payloads: ['{"error":"缺少 query"}']),
      steps: steps,
    );

    expect(steps, hasLength(1));
    expect(steps.single.summary, contains('失败'));
    expect(steps.single.hits, 0);
  });

  test('超预算的结果被裁到预算内且仍是合法 JSON', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(),
    ]);
    final hit = '{"chapter":1,"title":"第一章","text":"${'雨' * 60}"}';
    final big = '{"hits":[$hit,$hit,$hit]}';

    await _run(
      client,
      toolbox: _FakeToolbox(payloads: [big]),
      maxToolChars: 300,
    );

    final tool = client.seen.last.lastWhere((m) => m.role == LlmRole.tool);
    expect(tool.content.length, lessThanOrEqualTo(300));
    expect(jsonDecode(tool.content), isA<Map<String, Object?>>());
  });

  test('被预算裁短的章正文会带上 truncated，步骤也如实标注', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [
        LlmToolCall(id: 'call_2', name: 'get_chapter', arguments: '{"chapter":7}'),
      ]),
      const LlmTurn(),
    ]);
    final steps = <SearchStep>[];

    await _run(
      client,
      steps: steps,
      toolbox: _FakeToolbox(
        payloads: ['{"chapter":7,"offset":0,"text":"${'雨' * 300}"}'],
      ),
      maxToolChars: 200,
    );

    final tool = client.seen.last.lastWhere((m) => m.role == LlmRole.tool);
    final decoded = jsonDecode(tool.content) as Map<String, Object?>;
    expect(decoded['truncated'], isTrue);
    expect((decoded['text'] as String).length, lessThan(300));
    expect(steps.single.summary, contains('已截断'));
  });

  test('搜索结果被裁掉命中项时，步骤里说明了截断', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(),
    ]);
    final steps = <SearchStep>[];
    final hit = '{"chapter":1,"title":"第一章","text":"${'雨' * 40}"}';

    await _run(
      client,
      steps: steps,
      toolbox: _FakeToolbox(payloads: ['{"hits":[$hit,$hit,$hit]}']),
      maxToolChars: 210,
    );

    expect(steps.single.summary, contains('已截断'));
  });

  test('剩余预算不足 minRoomForCall 时直接跳过', () async {
    final client = _ScriptedClient([
      const LlmTurn(toolCalls: [_searchCall]),
      const LlmTurn(toolCalls: [
        LlmToolCall(id: 'call_2', name: 'search_in_book', arguments: '{"query":"风"}'),
      ]),
      const LlmTurn(),
    ]);

    await _run(
      client,
      toolbox: _FakeToolbox(
        payloads: ['{"hits":[{"chapter":1,"title":"第一章","text":"${'雨' * 60}"}]}'],
      ),
      maxToolChars: 250,
    );

    final tool = client.seen.last.lastWhere((m) => m.role == LlmRole.tool);
    expect(tool.content, contains('skipped: budget'));
  });
}
