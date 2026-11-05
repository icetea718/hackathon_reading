import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:coread/distill/llm/llm_client.dart';
import 'package:coread/distill/llm/llm_config.dart';
import 'package:coread/distill/llm/openai_llm_client.dart';

import '../support/fake_llm_server.dart';

void main() {
  late FakeLlmServer server;

  LlmConfig configFor(Uri baseUrl) => LlmConfig(
        baseUrl: baseUrl.toString(),
        model: 'test-model',
        apiKey: 'sk-test',
      );

  const messages = [LlmMessage(LlmRole.user, '你好')];

  test('streamChat yields deltas and stops on DONE', () async {
    server = await FakeLlmServer.start((request, _) async {
      await writeSse(request, [
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n',
        'data: [DONE]\n\n',
      ]);
    });
    addTearDown(server.stop);

    final client = OpenAiLlmClient(config: () => configFor(server.baseUrl));
    addTearDown(client.dispose);

    expect(await client.streamChat(messages).toList(), ['你', '好']);

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    expect(body['model'], 'test-model');
    expect(body['stream'], isTrue);
    expect(server.requests.single.headers.value('authorization'), 'Bearer sk-test');
  });

  test('completeJson returns message content', () async {
    server = await FakeLlmServer.start((request, _) async {
      await writeJson(request, {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': '{"ok":true}'},
          },
        ],
      });
    });
    addTearDown(server.stop);

    final client = OpenAiLlmClient(config: () => configFor(server.baseUrl));
    addTearDown(client.dispose);

    expect(await client.completeJson(messages), '{"ok":true}');

    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    expect(body['stream'], isFalse);
  });

  test('completeJson maps 401 to a readable error', () async {
    server = await FakeLlmServer.start((request, _) async {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('{"error":{"message":"invalid api key"}}');
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiLlmClient(config: () => configFor(server.baseUrl));
    addTearDown(client.dispose);

    await expectLater(
      client.completeJson(messages),
      throwsA(
        isA<LlmException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('invalid api key')),
      ),
    );
  });

  test('streamChat surfaces a non-200 response as LlmException', () async {
    server = await FakeLlmServer.start((request, _) async {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('bad request');
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiLlmClient(config: () => configFor(server.baseUrl));
    addTearDown(client.dispose);

    await expectLater(
      client.streamChat(messages).toList(),
      throwsA(isA<LlmException>().having((e) => e.statusCode, 'status', 400)),
    );
  });

  test('cancel stops the stream without throwing', () async {
    final keepAlive = Completer<void>();
    server = await FakeLlmServer.start((request, _) async {
      request.response.headers.set('content-type', 'text/event-stream');
      for (var i = 0; i < 100 && !keepAlive.isCompleted; i++) {
        request.response.write(
          'data: {"choices":[{"delta":{"content":"$i"}}]}\n\n',
        );
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await request.response.close();
    });
    addTearDown(() async {
      if (!keepAlive.isCompleted) keepAlive.complete();
      await server.stop();
    });

    final client = OpenAiLlmClient(config: () => configFor(server.baseUrl));
    addTearDown(client.dispose);

    final cancel = CancelToken();
    final received = <String>[];
    await for (final delta in client.streamChat(messages, cancel: cancel)) {
      received.add(delta);
      cancel.cancel();
    }

    expect(received, isNotEmpty);
    expect(received.first, '0');
  });

  test('an unconfigured client refuses to send', () async {
    final client = OpenAiLlmClient(
      config: () => const LlmConfig(
        baseUrl: 'http://127.0.0.1:1/v1',
        model: 'test-model',
        apiKey: '',
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.completeJson(messages),
      throwsA(
        isA<LlmException>().having((e) => e.statusCode, 'statusCode', isNull),
      ),
    );
  });
}
