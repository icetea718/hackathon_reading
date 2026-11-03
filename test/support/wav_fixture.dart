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
