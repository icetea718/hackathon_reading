import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/distill/llm/sse.dart';

void main() {
  test('ssePayload reads data lines only', () {
    expect(ssePayload('data: {"a":1}'), '{"a":1}');
    expect(ssePayload('event: ping'), isNull);
    expect(ssePayload('data: [DONE]'), '[DONE]');
  });

  test('ssePayload ignores blank lines and comments', () {
    expect(ssePayload(''), isNull);
    expect(ssePayload(': keep-alive'), isNull);
    expect(ssePayload('data:'), '');
  });

  test('ssePayload tolerates the optional space after the colon', () {
    expect(ssePayload('data:{"a":1}'), '{"a":1}');
    expect(ssePayload('data:   {"a":1}'), '  {"a":1}');
  });

  test('sseContentDelta extracts a streaming delta', () {
    expect(
      sseContentDelta('{"choices":[{"delta":{"content":"你"}}]}'),
      '你',
    );
    expect(sseContentDelta('{"choices":[{"delta":{}}]}'), isNull);
    expect(sseContentDelta('{"choices":[]}'), isNull);
    expect(sseContentDelta('not json'), isNull);
  });
}
