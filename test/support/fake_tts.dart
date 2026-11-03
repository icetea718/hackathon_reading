import 'dart:typed_data';

import 'package:hackathon_reading/tts/audio_output.dart';
import 'package:hackathon_reading/tts/tts_client.dart';

import 'wav_fixture.dart';

/// Replays canned audio and records what was asked for.
class FakeTtsClient implements TtsClient {
  FakeTtsClient({
    Uint8List? wav,
    this.failures = 0,
    this.pingResult = true,
  }) : wav = wav ?? makeWav(milliseconds: 60);

  /// Audio returned for every successful request.
  Uint8List wav;

  /// How many requests fail before one succeeds.
  int failures;

  bool pingResult;

  final List<String> texts = [];
  final List<String> voices = [];
  final List<double> speeds = [];
  bool disposed = false;

  @override
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  }) async {
    texts.add(text);
    voices.add(voice);
    speeds.add(speed);
    if (failures > 0) {
      failures--;
      throw const TtsException('HTTP 400: bad text', statusCode: 400);
    }
    return wav;
  }

  @override
  Future<bool> ping() async => pingResult;

  @override
  void dispose() {
    disposed = true;
  }
}

/// Records playback instead of touching the sound card.
class FakeAudioOutput implements AudioOutput {
  final List<String> played = [];
  int stops = 0;
  bool disposed = false;

  @override
  Future<void> playFile(String path) async {
    played.add(path);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
