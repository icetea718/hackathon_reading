import 'dart:math' as math;
import 'dart:typed_data';

/// Sample layout of a RIFF/WAVE buffer.
class WavInfo {
  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataStart,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// Offset of the first PCM byte.
  final int dataStart;

  /// Length of the PCM payload in bytes.
  final int dataLength;

  int get bytesPerFrame => (bitsPerSample ~/ 8) * channels;
}

/// Reads the WAVE header, or returns null when [bytes] is not 16-bit PCM WAV.
///
/// Ported from `parseWavHeader` in `synth.ts` of the reference plugin: chunk
/// sizes are padded to even lengths, so the walk uses `8 + size + (size & 1)`.
WavInfo? tryParseWavHeader(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final data = ByteData.sublistView(bytes);
  bool tag(int offset, String ascii) {
    for (var i = 0; i < ascii.length; i++) {
      if (bytes[offset + i] != ascii.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (!tag(0, 'RIFF') || !tag(8, 'WAVE')) return null;

  var sampleRate = 0;
  var channels = 0;
  var bitsPerSample = 0;
  var at = 12;
  while (at + 8 <= bytes.length) {
    final size = data.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (tag(at, 'fmt ') && body + 16 <= bytes.length) {
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (tag(at, 'data')) {
      final available = bytes.length - body;
      final length = size <= available ? size : available;
      if (sampleRate <= 0 || channels <= 0 || bitsPerSample != 16) return null;
      return WavInfo(
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
        dataStart: body,
        dataLength: length,
      );
    }
    at = body + size + (size & 1);
  }
  return null;
}

/// Playback length of a WAV buffer in milliseconds, or 0 when unparsable.
///
/// `PlaySoundW` reports nothing back, so the caller estimates the end of a
/// line from the audio itself.
int wavDurationMs(Uint8List bytes) {
  final info = tryParseWavHeader(bytes);
  if (info == null) return 0;
  final frameBytes = info.bytesPerFrame;
  if (frameBytes <= 0) return 0;
  final frames = info.dataLength / frameBytes;
  return (frames / info.sampleRate * 1000).round();
}

/// Soft knee above which samples are bent instead of clipped.
const double gainKnee = 24000;

/// Scales the PCM payload by [gain], bending loud samples through `tanh`.
///
/// Ported from `applyGain` in `player.ts`. Returns [wav] unchanged when the
/// gain is neutral or the format is not 16-bit PCM.
Uint8List applyGain(Uint8List wav, double gain) {
  if (gain == 1 || gain < 0) return wav;
  final info = tryParseWavHeader(wav);
  if (info == null || info.bitsPerSample != 16) return wav;

  final out = Uint8List.fromList(wav);
  final data = ByteData.sublistView(out);
  final end = info.dataStart + info.dataLength;
  for (var at = info.dataStart; at + 2 <= end; at += 2) {
    final sample = data.getInt16(at, Endian.little).toDouble();
    data.setInt16(at, _bend(sample * gain).round(), Endian.little);
  }
  return out;
}

double _bend(double value) {
  if (value > gainKnee) {
    final over = (value - gainKnee) / (32767 - gainKnee);
    return gainKnee + (32767 - gainKnee) * _tanh(over);
  }
  if (value < -gainKnee) {
    final over = (-value - gainKnee) / (32768 - gainKnee);
    return -gainKnee - (32768 - gainKnee) * _tanh(over);
  }
  return value;
}

/// `dart:math` has no hyperbolic tangent, and `exp` overflows past ~700.
double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
