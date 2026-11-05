import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/llm/llm_client.dart';

class _StubClient extends LlmClient {
  @override
  Stream<String> streamChat(List<LlmMessage> messages,
          {double? temperature, int? maxTokens, CancelToken? cancel}) =>
      const Stream.empty();

  @override
  Future<String> completeJson(List<LlmMessage> messages,
          {double? temperature, int? maxTokens, CancelToken? cancel}) async =>
      '';

  @override
  void dispose() {}
}

void main() {
  test('assistant 带 tool_calls 时输出 OpenAI 形状', () {
    const message = LlmMessage(
      LlmRole.assistant,
      '',
      toolCalls: [
        LlmToolCall(id: 'call_1', name: 'search_in_book', arguments: '{"query":"雨"}'),
      ],
    );
    expect(message.toJson(), {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': 'call_1',
          'type': 'function',
          'function': {'name': 'search_in_book', 'arguments': '{"query":"雨"}'},
        },
      ],
    });
  });

  test('tool 消息带 tool_call_id 且不带 tool_calls', () {
    const message = LlmMessage(LlmRole.tool, '{"hits":[]}', toolCallId: 'call_1');
    expect(message.toJson(), {
      'role': 'tool',
      'content': '{"hits":[]}',
      'tool_call_id': 'call_1',
    });
  });

  test('普通消息不带任何工具字段', () {
    expect(const LlmMessage(LlmRole.user, '你好').toJson(),
        {'role': 'user', 'content': '你好'});
  });

  test('LlmToolSpec 序列化成 function 包装', () {
    const spec = LlmToolSpec(
      name: 'get_chapter',
      description: '读某章',
      parameters: {'type': 'object'},
    );
    expect(spec.toJson(), {
      'type': 'function',
      'function': {
        'name': 'get_chapter',
        'description': '读某章',
        'parameters': {'type': 'object'},
      },
    });
  });

  test('LlmTurn.wantsTools 只在有 toolCalls 时为真', () {
    expect(const LlmTurn(content: '直接回答').wantsTools, isFalse);
    expect(
      const LlmTurn(toolCalls: [LlmToolCall(id: 'a', name: 'b', arguments: '{}')])
          .wantsTools,
      isTrue,
    );
  });

  test('没实现 completeTurn 的客户端明确报错而不是静默成功', () {
    expect(() => _StubClient().completeTurn(const []), throwsUnsupportedError);
  });
}
