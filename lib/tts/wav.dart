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

/// Container the voice service answered with.
enum AudioFormat { wav, mp3, unknown }

/// Guesses the container of an endpoint reply from its first bytes.
///
/// GitHub-style TTS endpoints answer WAV or MP3 depending on the engine, so the
/// player has to look at the payload instead of trusting a request parameter.
AudioFormat sniffAudioFormat(Uint8List bytes) {
  if (bytes.length >= 12 && _tagAt(bytes, 0, 'RIFF') && _tagAt(bytes, 8, 'WAVE')) {
    return tryParseWavHeader(bytes) != null ? AudioFormat.wav : AudioFormat.unknown;
  }
  if (bytes.length >= 3 && _tagAt(bytes, 0, 'ID3')) return AudioFormat.mp3;
  // MPEG frame sync: eleven set bits, then the version/layer bits.
  if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
    return AudioFormat.mp3;
  }
  return AudioFormat.unknown;
}

bool _tagAt(Uint8List bytes, int offset, String ascii) {
  if (offset + ascii.length > bytes.length) return false;
  for (var i = 0; i < ascii.length; i++) {
    if (bytes[offset + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

/// Silence trimmed off the head and kept at the tail, in milliseconds.
///
/// Engines pad every clip with silence (the VoxCPM path adds ~1.1 s of digital
/// silence), which turns a sentence-by-sentence pipeline into
/// "sentence, pause, stall, sentence". Peaks under [threshold] count as
/// silence; the kept tail is what makes lines sound separate without a gap.
Uint8List trimSilence(
  Uint8List wav, {
  int threshold = 320,
  int keepHeadMs = 30,
  int keepTailMs = 60,
  int windowMs = 10,
}) {
  final info = tryParseWavHeader(wav);
  if (info == null) return wav;
  final frameBytes = info.bytesPerFrame;
  if (frameBytes <= 0) return wav;
  final frames = info.dataLength ~/ frameBytes;
  if (frames <= 0) return wav;

  final data = ByteData.sublistView(wav);
  final window = math.max(1, info.sampleRate * windowMs ~/ 1000);

  /// True when any sample of the window starting at [frame] reaches the knee.
  bool loud(int frame) {
    final start = info.dataStart + frame * frameBytes;
    for (var i = 0; i < window; i++) {
      final at = start + i * frameBytes;
      if (at + frameBytes > wav.length) break;
      for (var channel = 0; channel < info.channels; channel++) {
        final sample = data.getInt16(at + channel * 2, Endian.little);
        if ((sample < 0 ? -sample : sample) >= threshold) return true;
      }
    }
    return false;
  }

  var first = 0;
  while (first + window <= frames && !loud(first)) {
    first += window;
  }
  if (first >= frames) return wav; // nothing but silence: keep it as it is

  var cursor = (frames - 1) - ((frames - 1) % window);
  while (cursor >= 0 && !loud(cursor)) {
    cursor -= window;
  }
  if (cursor < 0) return wav;
  final last = cursor;

  final head = info.sampleRate * keepHeadMs ~/ 1000;
  final tail = info.sampleRate * keepTailMs ~/ 1000;
  final from = math.max(0, first - head);
  final to = math.min(frames, last + window + tail);
  if (from == 0 && to >= frames) return wav;

  final start = info.dataStart + from * frameBytes;
  final length = (to - from) * frameBytes;
  final out = Uint8List(info.dataStart + length);
  out.setRange(0, info.dataStart, wav);
  out.setRange(info.dataStart, out.length, wav, start);

  // Keep the RIFF chunk sizes in step with the shortened payload.
  final header = ByteData.sublistView(out);
  header.setUint32(4, out.length - 8, Endian.little);
  header.setUint32(info.dataStart - 4, length, Endian.little);
  return out;
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
