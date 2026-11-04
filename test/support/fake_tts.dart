import 'dart:async';
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
    this.probeResult = const TtsProbe(ok: true, message: '语音服务可用：fake'),
  }) : wav = wav ?? makeWav(milliseconds: 60);

  /// Audio returned for every successful request.
  Uint8List wav;

  /// How many requests fail before one succeeds.
  int failures;

  bool pingResult;

  TtsProbe probeResult;

  final List<String> texts = [];
  final List<String> voices = [];
  final List<double> speeds = [];

  /// Requests that were in flight at the same time, at most 2 in practice.
  int peakInFlight = 0;
  int _inFlight = 0;

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
    _inFlight++;
    if (_inFlight > peakInFlight) peakInFlight = _inFlight;
    try {
      await Future<void>.delayed(Duration.zero);
      if (failures > 0) {
        failures--;
        throw const TtsException('HTTP 400: bad text', statusCode: 400);
      }
      return wav;
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<TtsProbe> probe() async => probeResult;

  @override
  Future<bool> ping() async => pingResult;

  @override
  void dispose() {
    disposed = true;
  }
}

/// Records playback instead of touching the sound card.
class FakeAudioOutput implements AudioOutput {
  FakeAudioOutput({this.defaultDelay = const Duration(milliseconds: 10)});

  /// Waited when the caller could not tell how long the clip is.
  final Duration defaultDelay;

  final List<String> played = [];

  /// Durations handed to [playFile], in order.
  final List<Duration?> durations = [];

  int stops = 0;
  bool disposed = false;

  Completer<void>? _interrupted;

  @override
  Future<void> playFile(String path, {Duration? duration}) async {
    played.add(path);
    durations.add(duration);
    final token = _interrupted = Completer<void>();
    try {
      await Future.any<void>([
        Future<void>.delayed(duration ?? defaultDelay),
        token.future,
      ]);
    } finally {
      if (identical(_interrupted, token)) _interrupted = null;
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    final token = _interrupted;
    if (token != null && !token.isCompleted) token.complete();
  }

  @override
  void dispose() {
    disposed = true;
  }
}
