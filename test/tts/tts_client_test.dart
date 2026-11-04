import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/tts/tts_client.dart';
import 'package:hackathon_reading/tts/tts_config.dart';

import '../support/wav_fixture.dart';

class _FakeSpeechServer {
  _FakeSpeechServer._(this._server);

  final HttpServer _server;
  final List<HttpRequest> requests = [];
  final List<String> bodies = [];

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<_FakeSpeechServer> start(
    Future<void> Function(HttpRequest request, _FakeSpeechServer server) handler,
  ) async {
    final server = _FakeSpeechServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen((request) async {
      server.requests.add(request);
      server.bodies.add(await utf8.decoder.bind(request).join());
      await handler(request, server);
    });
    return server;
  }

  Future<void> stop() => _server.close(force: true);
}

TtsConfig _configFor(String baseUrl) => TtsConfig(
      baseUrl: baseUrl,
      voice: 'xll',
      speed: 1,
      volume: 1,
      enabled: true,
      autoSpeak: false,
    );

void main() {
  test('posts the OpenAI speech payload and returns the WAV', () async {
    final wav = makeWav(milliseconds: 40);
    final server = await _FakeSpeechServer.start((request, _) async {
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.add(wav);
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiTtsClient(config: () => _configFor(server.baseUrl));
    addTearDown(client.dispose);

    final audio = await client.synthesize('你好。', voice: 'dfy', speed: 1.2);

    expect(audio, wav);
    expect(server.requests.single.uri.path, '/v1/audio/speech');
    final body = jsonDecode(server.bodies.single) as Map<String, Object?>;
    expect(body['model'], 'gpt-sovits');
    expect(body['input'], '你好。');
    expect(body['voice'], 'dfy');
    expect(body['speed'], 1.2);
    expect(body['response_format'], 'wav');
  });

  test('falls back to the bare speech path when v1 is missing', () async {
    final wav = makeWav(milliseconds: 40);
    final server = await _FakeSpeechServer.start((request, _) async {
      if (request.uri.path == '/v1/audio/speech') {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{"error":"not found"}');
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.add(wav);
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiTtsClient(config: () => _configFor(server.baseUrl));
    addTearDown(client.dispose);

    final audio = await client.synthesize('你好。', voice: 'xll', speed: 1);

    expect(audio, wav);
    expect(
      server.requests.map((request) => request.uri.path),
      ['/v1/audio/speech', '/audio/speech'],
    );
  });

  test('accepts an MP3 answer and builds the root from a full endpoint',
      () async {
    // The edge voices of chino-tts answer MP3 even though WAV was requested.
    final mp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x64, 0, 0, 0, 0]);
    final server = await _FakeSpeechServer.start((request, _) async {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.add(mp3);
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiTtsClient(
      config: () => _configFor('${server.baseUrl}/v1/audio/speech'),
    );
    addTearDown(client.dispose);

    expect(await client.synthesize('你好。', voice: 'zhino', speed: 1), mp3);
    expect(server.requests.single.uri.path, '/v1/audio/speech');
  });

  test('surfaces a rejected request with its status and body', () async {
    final server = await _FakeSpeechServer.start((request, _) async {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('text is empty');
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiTtsClient(config: () => _configFor(server.baseUrl));
    addTearDown(client.dispose);

    await expectLater(
      client.synthesize('你好。', voice: 'xll', speed: 1),
      throwsA(
        isA<TtsException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('text is empty')),
      ),
    );
  });

  test('rejects a 200 response that is not audio', () async {
    final server = await _FakeSpeechServer.start((request, _) async {
      request.response.write('<html>proxy error</html>');
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiTtsClient(config: () => _configFor(server.baseUrl));
    addTearDown(client.dispose);

    await expectLater(
      client.synthesize('你好。', voice: 'xll', speed: 1),
      throwsA(
        isA<TtsException>()
            .having((e) => e.message, 'message', contains('不是音频')),
      ),
    );
  });

  test('reports an unreachable service as a transport error', () async {
    final server = await _FakeSpeechServer.start((request, _) async {
      await request.response.close();
    });
    final baseUrl = server.baseUrl;
    await server.stop();

    final client = OpenAiTtsClient(config: () => _configFor(baseUrl));
    addTearDown(client.dispose);

    await expectLater(
      client.synthesize('你好。', voice: 'xll', speed: 1),
      throwsA(
        isA<TtsException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('无法连接')),
      ),
    );
  });

  test('ping reflects the health endpoint', () async {
    final server = await _FakeSpeechServer.start((request, _) async {
      request.response.write('{"ready":true,"state":"available"}');
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiTtsClient(config: () => _configFor(server.baseUrl));
    addTearDown(client.dispose);

    expect(await client.ping(), isTrue);
    expect(server.requests.single.uri.path, '/health');

    final dead = OpenAiTtsClient(
      config: () => _configFor('http://127.0.0.1:1'),
    );
    addTearDown(dead.dispose);
    expect(await dead.ping(), isFalse);
  });

  test('describes the service and warns about an unknown voice', () async {
    final server = await _FakeSpeechServer.start((request, _) async {
      request.response.write(
        '{"ok":true,"service":"chino-tts","default":"zhino",'
        '"voices":["zhino","zhino-clone"]}',
      );
      await request.response.close();
    });
    addTearDown(server.stop);

    final client = OpenAiTtsClient(config: () => _configFor(server.baseUrl));
    addTearDown(client.dispose);

    final probe = await client.probe();

    expect(probe.ok, isTrue);
    expect(probe.message, contains('chino-tts'));
    expect(probe.message, contains('默认音色 zhino'));
    // The configured voice is xll, which this service does not have.
    expect(probe.message, contains('没有音色「xll」'));
    expect(probe.message, contains('zhino-clone'));
  });

  test('explains a service that is not there', () async {
    final client = OpenAiTtsClient(
      config: () => _configFor('http://127.0.0.1:1'),
    );
    addTearDown(client.dispose);

    final probe = await client.probe();

    expect(probe.ok, isFalse);
    expect(probe.message, contains('连不上'));
  });

  test('refuses to send without an address', () async {
    final client = OpenAiTtsClient(
      config: () => const TtsConfig(
        baseUrl: '',
        voice: 'xll',
        speed: 1,
        volume: 1,
        enabled: true,
        autoSpeak: false,
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.synthesize('你好。', voice: 'xll', speed: 1),
      throwsA(
        isA<TtsException>().having((e) => e.message, 'message', '未配置语音服务'),
      ),
    );
  });
}
