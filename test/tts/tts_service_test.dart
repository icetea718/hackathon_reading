import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/tts/audio_output.dart';
import 'package:hackathon_reading/tts/tts_config.dart';
import 'package:hackathon_reading/tts/tts_service.dart';
import 'package:hackathon_reading/tts/wav.dart';

import '../support/fake_tts.dart';
import '../support/wav_fixture.dart';

const _config = TtsConfig(
  baseUrl: 'http://127.0.0.1:9880',
  voice: 'xll',
  speed: 1,
  volume: 1,
  autoSpeak: false,
);

/// Reads the bytes handed to the player before the service deletes the file.
class _ReadingOutput extends FakeAudioOutput {
  final List<Uint8List> files = [];

  @override
  Future<void> playFile(String path, {Duration? duration}) async {
    files.add(await File(path).readAsBytes());
    await super.playFile(path, duration: duration);
  }
}

/// Polls on the real event loop; synthesis writes files, so fixed sleeps race
/// with a loaded machine.
Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition not met within 2s');
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tts_service_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  TtsService build(
    FakeTtsClient client,
    FakeAudioOutput output, {
    TtsConfig Function()? config,
    Duration Function(Uint8List)? durationOf,
  }) {
    return TtsService(
      client: client,
      output: output,
      config: config ?? () => _config,
      tempDirectory: () async => tempDir,
      durationOf: durationOf ?? (_) => const Duration(milliseconds: 10),
    );
  }

  test('speaks the reply sentence by sentence', () async {
    final client = FakeTtsClient();
    final output = FakeAudioOutput();
    final service = build(client, output);
    addTearDown(service.dispose);

    await service.speak('福贵输了钱。家珍哭了！');

    expect(client.texts, ['福贵输了钱。', '家珍哭了！']);
    expect(client.voices, everyElement('xll'));
    expect(output.played, hasLength(2));
    expect(service.status.phase, TtsPhase.idle);
    expect(service.status.error, isNull);
  });

  test('sends the tail of a reply as one longer request', () async {
    final client = FakeTtsClient();
    final output = FakeAudioOutput();
    final service = build(
      client,
      output,
      durationOf: (_) => const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);

    await service.speak('第一句。第二句。第三句。第四句。');

    // The first sentence starts fast; the rest travels as one request, so the
    // reply has a single seam instead of one per sentence.
    expect(client.texts, ['第一句。', '第二句。第三句。第四句。']);
    expect(output.played, hasLength(2));
  });

  test('reports synthesizing then playing then idle', () async {
    final service = build(FakeTtsClient(), FakeAudioOutput());
    addTearDown(service.dispose);
    final seen = <TtsPhase>[];
    final subscription = service.statuses.listen((s) => seen.add(s.phase));
    addTearDown(subscription.cancel);

    await service.speak('福贵输了钱。');
    await Future<void>.delayed(Duration.zero);

    expect(seen.first, TtsPhase.synthesizing);
    expect(seen, contains(TtsPhase.playing));
    expect(seen.last, TtsPhase.idle);
  });

  test('does nothing for a blank reply', () async {
    final client = FakeTtsClient();
    final output = FakeAudioOutput();
    final service = build(client, output);
    addTearDown(service.dispose);

    await service.speak('  \n ');

    expect(client.texts, isEmpty);
    expect(output.played, isEmpty);
    expect(service.status.phase, TtsPhase.idle);
  });

  test('speaks whenever asked, even with auto read on', () async {
    final client = FakeTtsClient();
    final service = build(
      client,
      FakeAudioOutput(),
      config: () => _config.copyWith(autoSpeak: true),
    );
    addTearDown(service.dispose);

    await service.speak('福贵输了钱。');

    expect(client.texts, ['福贵输了钱。']);
  });

  test('retries once without punctuation', () async {
    final client = FakeTtsClient(failures: 1);
    final service = build(client, FakeAudioOutput());
    addTearDown(service.dispose);

    await service.speak('好耶！');

    expect(client.texts, ['好耶！', '好耶']);
    expect(service.status.error, isNull);
  });

  test('surfaces a failure once the retry fails too', () async {
    final client = FakeTtsClient(failures: 5);
    final service = build(client, FakeAudioOutput());
    addTearDown(service.dispose);

    await service.speak('好耶！真的吗？');

    expect(service.status.error, contains('HTTP 400'));
    expect(service.status.phase, TtsPhase.idle);
  });

  test('stop cuts playback and skips the rest of the reply', () async {
    final client = FakeTtsClient();
    final output = FakeAudioOutput();
    final service = build(
      client,
      output,
      durationOf: (_) => const Duration(milliseconds: 200),
    );
    addTearDown(service.dispose);

    final speaking = service.speak('第一句。第二句。第三句。');
    await _waitUntil(() => output.played.isNotEmpty);
    await service.stop();
    await speaking;

    expect(output.played, hasLength(1));
    expect(output.stops, greaterThan(0));
    expect(service.status.phase, TtsPhase.idle);
  });

  test('a newer reply replaces the one playing', () async {
    final client = FakeTtsClient();
    final output = FakeAudioOutput();
    final service = build(
      client,
      output,
      durationOf: (_) => const Duration(milliseconds: 150),
    );
    addTearDown(service.dispose);

    final first = service.speak('旧的回复。还有一句。');
    await _waitUntil(() => output.played.isNotEmpty);
    final second = service.speak('新的回复。');
    await Future.wait([first, second]);

    expect(client.texts.first, '旧的回复。');
    expect(client.texts.last, '新的回复。');
    expect(output.played, hasLength(2));
  });

  test('applies the configured volume before playing', () async {
    final output = _ReadingOutput();
    final service = build(
      FakeTtsClient(wav: makeWav(amplitude: 12000)),
      output,
      config: () => _config.copyWith(volume: 0.5),
    );
    addTearDown(service.dispose);

    await service.speak('福贵输了钱。');

    expect(output.files, hasLength(1));
    final played = ByteData.sublistView(output.files.single);
    var peak = 0;
    for (var at = 44; at + 2 <= output.files.single.length; at += 2) {
      final sample = played.getInt16(at, Endian.little).abs();
      if (sample > peak) peak = sample;
    }
    expect(peak, lessThan(7000));
    expect(peak, greaterThan(1000));
  });

  test('reports a playback failure', () async {
    final output = _ThrowingOutput();
    final service = build(FakeTtsClient(), output);
    addTearDown(service.dispose);

    await service.speak('福贵输了钱。');

    expect(service.status.error, contains('无法播放'));
  });

  test('trims the padding an engine leaves around each line', () async {
    final padded = makePaddedWav(leadMs: 400, speechMs: 80, tailMs: 400);
    final output = _ReadingOutput();
    final service = build(FakeTtsClient(wav: padded), output);
    addTearDown(service.dispose);

    await service.speak('福贵输了钱。');

    final played = output.files.single;
    expect(wavDurationMs(played), lessThan(wavDurationMs(padded) - 500));
    expect(wavDurationMs(played), greaterThan(60));
  });

  test('keeps a second request in flight while a line plays', () async {
    final client = FakeTtsClient();
    final service = build(
      client,
      FakeAudioOutput(),
      durationOf: (_) => const Duration(milliseconds: 40),
    );
    addTearDown(service.dispose);

    // Four sentences too long to be merged into one request each pair.
    final reply = ['甲', '乙', '丙', '丁'].map((c) => '${c * 80}。').join();
    await service.speak(reply);

    expect(client.texts, hasLength(4));
    expect(client.peakInFlight, 2);
  });
}

class _ThrowingOutput extends FakeAudioOutput {
  @override
  Future<void> playFile(String path, {Duration? duration}) async {
    throw TtsPlaybackException('无法播放音频: $path');
  }
}
