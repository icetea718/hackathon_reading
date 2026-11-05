import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:coread/tts/edge/edge_voices.dart';
import 'package:coread/tts/routing_tts_client.dart';
import 'package:coread/tts/tts_client.dart';
import 'package:coread/tts/tts_config.dart';
import 'package:coread/tts/tts_voices.dart';

TtsConfig _configWith(String voice) => TtsConfig(
      baseUrl: 'http://127.0.0.1:1',
      voice: voice,
      speed: 1,
      volume: 1,
      autoSpeak: false,
    );

/// Records what it was asked to speak, and answers with one fake byte.
class _FakeTtsClient implements TtsClient {
  _FakeTtsClient({this.ok = true, this.message = 'ok'});

  final bool ok;
  final String message;
  final List<String> spoken = <String>[];

  @override
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  }) async {
    spoken.add(voice);
    return Uint8List.fromList(<int>[1, 2, 3]);
  }

  @override
  Future<TtsProbe> probe() async => TtsProbe(ok: ok, message: message);

  @override
  Future<bool> ping() async => ok;

  @override
  void dispose() {}
}

void main() {
  group('voice catalog', () {
    test('lists the built-in voices first', () {
      final voices = TtsVoices.fallback;
      expect(voices.first.builtIn, isTrue);
      expect(
        voices.where((v) => v.builtIn).map((v) => v.id),
        <String>['zhino', 'zhino-quiet', 'xiaoyi', 'xiaoxiao', 'laopai'],
      );
    });

    test('offers a male reader, not only the assistant girl', () {
      final laopai = EdgeVoices.resolve('laopai');

      expect(laopai.id, 'laopai');
      expect(laopai.voice, 'zh-CN-YunyangNeural');
      expect(laopai.locale, 'zh-CN');
      expect(TtsVoices.isBuiltIn('laopai'), isTrue);
      // Slower and lower than the assistant voice: a man reading aloud, not a
      // news anchor at broadcast speed.
      expect(laopai.rate, lessThan(0));
      expect(laopai.pitch, lessThan(0));
    });

    test('no longer offers names the service never had', () {
      final ids = TtsVoices.fallback.map((v) => v.id).toList();
      // `xll` and `dfy` used to be offered while chino-tts silently answered
      // with its default voice.
      expect(ids, isNot(contains('xll')));
      expect(ids, isNot(contains('dfy')));
      expect(ids, containsAll(<String>['zhino-clone', 'xiaoyu', 'luxun']));
    });

    test('knows which ids need no local service', () {
      expect(TtsVoices.isBuiltIn('zhino'), isTrue);
      expect(TtsVoices.isBuiltIn('zhino-clone'), isFalse);
      expect(TtsVoices.isBuiltIn('nonsense'), isFalse);
    });

    test('labels an unknown id with itself', () {
      expect(TtsVoices.labelOf('female'), 'female');
    });
  });

  group('catalog from the service', () {
    late HttpServer server;
    late List<String> requests;

    setUp(() async {
      requests = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path != '/voices') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.write(jsonEncode(<String, Object>{
          'default': 'zhino',
          'profiles': <String, Object>{
            'zhino': <String, Object>{'label': '晓伊 · 服务端叫法'},
            'zhino-clone': <String, Object>{'label': '智乃 · 克隆'},
            'brand-new': <String, Object>{'label': '新音色'},
          },
        }));
        await request.response.close();
      });
    });

    tearDown(() async => server.close(force: true));

    test('merges served profiles with the built-in catalog', () async {
      final voices = await TtsVoices.load('http://127.0.0.1:${server.port}');
      final ids = voices.map((v) => v.id).toList();
      // Served voices keep their own order, the app's own voices fill the gaps
      // and come first so the zero-setup ones are one tap away.
      expect(ids, containsAll(<String>['zhino', 'zhino-clone', 'brand-new']));
      expect(ids, containsAll(<String>['zhino-quiet', 'xiaoyi', 'xiaoxiao']));
      expect(voices.firstWhere((v) => v.id == 'zhino').builtIn, isTrue);
      expect(voices.firstWhere((v) => v.id == 'zhino-clone').builtIn, isFalse);
      expect(voices.firstWhere((v) => v.id == 'brand-new').builtIn, isFalse);
    });

    test('takes the service label when it has one', () async {
      final voices = await TtsVoices.load('http://127.0.0.1:${server.port}');
      expect(
        voices.firstWhere((v) => v.id == 'zhino').label,
        '晓伊 · 服务端叫法',
      );
    });

    test('strips a pasted speech endpoint before asking', () async {
      await TtsVoices.load(
        'http://127.0.0.1:${server.port}/v1/audio/speech',
      );
      expect(requests, <String>['/voices']);
    });
  });

  group('catalog without a service', () {
    test('falls back instead of going empty', () async {
      final voices = await TtsVoices.load('http://127.0.0.1:1');
      expect(voices, isNotEmpty);
      expect(voices.first.builtIn, isTrue);
    });

    test('falls back on an empty address', () async {
      final voices = await TtsVoices.load('   ');
      expect(
        voices.map((v) => v.id),
        TtsVoices.fallback.map((v) => v.id),
      );
    });
  });

  group('routing', () {
    test('built-in voice speaks online, without the local service', () async {
      final builtIn = _FakeTtsClient();
      final service = _FakeTtsClient();
      final client = RoutingTtsClient(
        config: () => _configWith('zhino'),
        builtIn: builtIn,
        service: service,
      );

      await client.synthesize('你好。', voice: 'zhino', speed: 1);

      expect(builtIn.spoken, <String>['zhino']);
      expect(service.spoken, isEmpty);
    });

    test('the male reader also speaks without the local service', () async {
      final builtIn = _FakeTtsClient();
      final service = _FakeTtsClient();
      final client = RoutingTtsClient(
        config: () => _configWith('laopai'),
        builtIn: builtIn,
        service: service,
      );

      await client.synthesize('你好。', voice: 'laopai', speed: 1);

      expect(builtIn.spoken, <String>['laopai']);
      expect(service.spoken, isEmpty);
    });

    test('clone voice goes to the local service', () async {
      final builtIn = _FakeTtsClient();
      final service = _FakeTtsClient();
      final client = RoutingTtsClient(
        config: () => _configWith('zhino-clone'),
        builtIn: builtIn,
        service: service,
      );

      await client.synthesize('你好。', voice: 'zhino-clone', speed: 1);

      expect(service.spoken, <String>['zhino-clone']);
      expect(builtIn.spoken, isEmpty);
    });

    test('a failing clone voice says the service is the problem', () async {
      final client = RoutingTtsClient(
        config: () => _configWith('zhino-clone'),
        builtIn: _FakeTtsClient(message: '内置音色可用'),
        service: _FakeTtsClient(
          ok: false,
          message: '连不上 http://127.0.0.1:8766（拒绝连接）',
        ),
      );

      final probe = await client.probe();

      expect(probe.ok, isFalse);
      expect(probe.message, contains('chino-tts'));
      expect(probe.message, contains('拒绝连接'));
      // The online engine still works, and the user is told so.
      expect(probe.message, contains('内置音色可用'));
    });

    test('a working built-in voice reports success on its own', () async {
      final client = RoutingTtsClient(
        config: () => _configWith('zhino'),
        builtIn: _FakeTtsClient(message: '内置音色可用：晓伊'),
        service: _FakeTtsClient(ok: false, message: '连不上 127.0.0.1:8766'),
      );

      final probe = await client.probe();

      expect(probe.ok, isTrue);
      expect(probe.message, '内置音色可用：晓伊');
    });
  });
}
