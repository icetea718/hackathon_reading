import 'dart:typed_data';

import 'edge/edge_tts_client.dart';
import 'tts_client.dart';
import 'tts_config.dart';
import 'tts_voices.dart';

/// Speaks each voice through the engine that can actually produce it.
///
/// The built-in online voices need nothing but the network, so the companion has
/// a voice on a machine where `chino-tts` was never installed. The clone voices
/// need that service, its reference audio and its model — asking for one of them
/// is asking for the local server, so there is no silent substitution: the error
/// says which half is missing.
class RoutingTtsClient implements TtsClient {
  RoutingTtsClient({
    required this.config,
    TtsClient? builtIn,
    TtsClient? service,
  })  : _builtIn = builtIn ?? EdgeTtsClient(config: config),
        _service = service ?? OpenAiTtsClient(config: config);

  /// Live snapshot of the settings, for `probe()`'s choice of engine.
  final TtsConfig Function() config;

  final TtsClient _builtIn;
  final TtsClient _service;

  @override
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  }) {
    final client = TtsVoices.isBuiltIn(voice) ? _builtIn : _service;
    return client.synthesize(text, voice: voice, speed: speed);
  }

  @override
  Future<TtsProbe> probe() async {
    final voice = config().voice;
    if (TtsVoices.isBuiltIn(voice)) {
      final edge = await _builtIn.probe();
      if (edge.ok) return edge;
      final service = await _service.probe();
      return TtsProbe(
        ok: false,
        message: '${edge.message}；本机服务：${service.message}',
      );
    }
    final service = await _service.probe();
    if (service.ok) return service;
    final edge = await _builtIn.probe();
    return TtsProbe(
      ok: false,
      message: '音色「${TtsVoices.labelOf(voice)}」要本机 chino-tts：'
          '${service.message}；内置音色状态：${edge.message}',
    );
  }

  @override
  Future<bool> ping() async => (await probe()).ok;

  @override
  void dispose() {
    _builtIn.dispose();
    _service.dispose();
  }
}
