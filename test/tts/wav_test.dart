import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:coread/tts/wav.dart';

import '../support/wav_fixture.dart';

/// Offset of a sample inside the mono fixture, past the 44-byte header.
int _at(int frame) => 44 + frame * 2;

void main() {
  test('reads the header of a 16-bit WAV', () {
    final wav = makeWav(sampleRate: 32000, channels: 2, milliseconds: 250);
    final info = tryParseWavHeader(wav);

    expect(info, isNotNull);
    expect(info!.sampleRate, 32000);
    expect(info.channels, 2);
    expect(info.bitsPerSample, 16);
    expect(info.dataStart, 44);
    expect(info.dataLength, wav.length - 44);
  });

  test('rejects buffers that are not WAV', () {
    expect(tryParseWavHeader(Uint8List.fromList(List.filled(64, 7))), isNull);
    expect(tryParseWavHeader(Uint8List(10)), isNull);
  });

  test('derives the duration from the payload size', () {
    expect(wavDurationMs(makeWav(milliseconds: 500)), closeTo(500, 2));
    expect(wavDurationMs(Uint8List(0)), 0);
  });

  test('leaves audio untouched at unity gain', () {
    final wav = makeWav();
    expect(identical(applyGain(wav, 1), wav), isTrue);
  });

  test('scales every sample by the gain', () {
    final wav = makeWav(amplitude: 10000);
    final quieter = applyGain(wav, 0.5);
    final before = ByteData.sublistView(wav);
    final after = ByteData.sublistView(quieter);

    expect(after.lengthInBytes, before.lengthInBytes);
    for (final frame in [15, 16, 40, 77]) {
      expect(
        after.getInt16(_at(frame), Endian.little),
        (before.getInt16(_at(frame), Endian.little) * 0.5).round(),
      );
    }
  });

  test('bends loud samples instead of wrapping around', () {
    final wav = makeWav(amplitude: 32000);
    final louder = applyGain(wav, 3);
    final data = ByteData.sublistView(louder);

    var peak = 0;
    for (var at = 44; at + 2 <= louder.length; at += 2) {
      final sample = data.getInt16(at, Endian.little);
      expect(sample, inInclusiveRange(-32768, 32767));
      if (sample.abs() > peak) peak = sample.abs();
    }
    // Straight multiplication would have wrapped at 32767 and stayed quiet.
    expect(peak, greaterThan(30000));
  });

  group('sniffAudioFormat', () {
    test('recognises a WAV answer', () {
      expect(sniffAudioFormat(makeWav(milliseconds: 20)), AudioFormat.wav);
    });

    test('recognises the MP3 the edge voices answer with', () {
      expect(
        sniffAudioFormat(Uint8List.fromList([0x49, 0x44, 0x33, 4, 0, 0])),
        AudioFormat.mp3,
      );
      expect(
        sniffAudioFormat(Uint8List.fromList([0xFF, 0xFB, 0x90, 0x64])),
        AudioFormat.mp3,
      );
    });

    test('rejects HTML and empty bodies', () {
      expect(
        sniffAudioFormat(Uint8List.fromList('<html>'.codeUnits)),
        AudioFormat.unknown,
      );
      expect(sniffAudioFormat(Uint8List(0)), AudioFormat.unknown);
    });
  });

  group('trimSilence', () {
    test('cuts the padded head and tail off a line', () {
      final padded = makePaddedWav(leadMs: 500, speechMs: 120, tailMs: 900);
      final trimmed = trimSilence(padded);

      expect(wavDurationMs(padded), closeTo(1520, 3));
      // Speech plus the kept margins only, so the padding never plays.
      expect(wavDurationMs(trimmed), lessThan(300));
      expect(wavDurationMs(trimmed), greaterThan(150));
      expect(tryParseWavHeader(trimmed), isNotNull);
    });

    test('keeps the RIFF and data sizes consistent', () {
      final trimmed = trimSilence(
        makePaddedWav(leadMs: 300, speechMs: 100, tailMs: 300),
      );
      final data = ByteData.sublistView(trimmed);
      final info = tryParseWavHeader(trimmed)!;

      expect(data.getUint32(4, Endian.little), trimmed.length - 8);
      expect(data.getUint32(info.dataStart - 4, Endian.little), info.dataLength);
    });

    test('leaves a clip without padding alone', () {
      final wav = makeWav(milliseconds: 120);
      expect(identical(trimSilence(wav), wav), isTrue);
    });

    test('leaves a buffer that is not WAV alone', () {
      final bytes = Uint8List.fromList('<html>'.codeUnits);
      expect(identical(trimSilence(bytes), bytes), isTrue);
    });
  });
}
