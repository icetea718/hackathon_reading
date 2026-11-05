import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/distill/llm/llm_config.dart';
import 'package:coread/distill/llm/openai_llm_client.dart';
import '../support/fake_llm_server.dart';

void main() {
  const messages = [LlmMessage(LlmRole.user, '雨意味着什么')];
  const tools = [
    LlmToolSpec(
      name: 'search_in_book',
      description: '书内检索',
      parameters: {'type': 'object'},
    ),
  ];

  test('带 tools 的请求体含 tools 与 tool_choice，且 stream 为 false', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_9',
                  'type': 'function',
                  'function': {'name': 'search_in_book', 'arguments': '{"query":"雨"}'},
                },
              ],
            },
          },
        ],
      });
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    final turn = await client.completeTurn(messages, tools: tools);

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    expect(body['stream'], isFalse);
    expect(body['tool_choice'], 'auto');
    expect((body['tools'] as List).single, {
      'type': 'function',
      'function': {
        'name': 'search_in_book',
        'description': '书内检索',
        'parameters': {'type': 'object'},
      },
    });
    expect(turn.content, '');
    expect(turn.toolCalls.single.id, 'call_9');
    expect(turn.toolCalls.single.name, 'search_in_book');
    expect(turn.toolCalls.single.arguments, '{"query":"雨"}');
  });

  test('不带 tools 的请求体里没有 tools 键', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {
        'choices': [
          {'message': {'role': 'assistant', 'content': '直接回答'}},
        ],
      });
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    final turn = await client.completeTurn(messages);

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    expect(body.containsKey('tools'), isFalse);
    expect(body.containsKey('tool_choice'), isFalse);
    expect(turn.content, '直接回答');
    expect(turn.toolCalls, isEmpty);
  });

  test('tool 角色与 tool_calls 原样发到线上', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {
        'choices': [
          {'message': {'role': 'assistant', 'content': '好了'}},
        ],
      });
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    await client.completeTurn([
      const LlmMessage(LlmRole.assistant, '', toolCalls: [
        LlmToolCall(id: 'call_1', name: 'search_in_book', arguments: '{}'),
      ]),
      const LlmMessage(LlmRole.tool, '{"hits":[]}', toolCallId: 'call_1'),
    ]);

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    final sent = body['messages'] as List;
    expect((sent[0] as Map)['tool_calls'], isA<List>());
    expect((sent[1] as Map)['role'], 'tool');
    expect((sent[1] as Map)['tool_call_id'], 'call_1');
  });

  test('响应没有 message 时抛出可读异常', () async {
    final server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {'choices': []});
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    expect(client.completeTurn(messages), throwsA(isA<LlmException>()));
  });

  test('400 且正文提到 tools 时保留状态码与正文片段', () async {
    final server = await FakeLlmServer.start((request, _) async {
      request.response.statusCode = 400;
      await writeJson(request, {'error': {'message': 'tools are not supported'}});
    });
    addTearDown(server.stop);
    final client = OpenAiLlmClient(
      config: () => LlmConfig(
        baseUrl: server.baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.completeTurn(messages, tools: tools),
      throwsA(isA<LlmException>()
          .having((e) => e.statusCode, 'statusCode', 400)
          .having((e) => e.message, 'message', contains('tools'))),
    );
  });
}
