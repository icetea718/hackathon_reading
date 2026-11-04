import 'dart:math' as math;
import 'dart:typed_data';

/// Builds a 16-bit PCM WAV buffer for tests.
///
/// [milliseconds] drives the data length, so `wavDurationMs` round-trips to
/// roughly the same value.
Uint8List makeWav({
  int sampleRate = 24000,
  int channels = 1,
  int milliseconds = 100,
  int amplitude = 8000,
}) {
  final frames = (sampleRate * milliseconds / 1000).round();
  final dataBytes = frames * channels * 2;
  final bytes = Uint8List(44 + dataBytes);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataBytes, Endian.little);

  for (var frame = 0; frame < frames; frame++) {
    final sample = (amplitude * math.sin(frame / 10)).round();
    for (var channel = 0; channel < channels; channel++) {
      data.setInt16(44 + (frame * channels + channel) * 2, sample,
          Endian.little);
    }
  }
  return bytes;
}

/// Builds a WAV padded with silence, the way speech engines return clips.
///
/// The VoxCPM path of chino-tts appends about a second of digital silence to
/// every line; [makePaddedWav] reproduces that so trimming can be tested.
Uint8List makePaddedWav({
  int sampleRate = 24000,
  int leadMs = 300,
  int speechMs = 80,
  int tailMs = 300,
  int amplitude = 8000,
}) {
  final head = makeWav(
    sampleRate: sampleRate,
    milliseconds: leadMs,
    amplitude: 0,
  );
  final speech = makeWav(
    sampleRate: sampleRate,
    milliseconds: speechMs,
    amplitude: amplitude,
  );
  final tail = makeWav(
    sampleRate: sampleRate,
    milliseconds: tailMs,
    amplitude: 0,
  );

  final body = BytesBuilder()
    ..add(head.sublist(44))
    ..add(speech.sublist(44))
    ..add(tail.sublist(44));
  final payload = body.takeBytes();
  final bytes = Uint8List(44 + payload.length);
  bytes.setRange(0, 44, head.sublist(0, 44));
  bytes.setRange(44, bytes.length, payload);

  final data = ByteData.sublistView(bytes);
  data.setUint32(4, 36 + payload.length, Endian.little);
  data.setUint32(40, payload.length, Endian.little);
  return bytes;
}
