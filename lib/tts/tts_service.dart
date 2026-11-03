import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'audio_output.dart';
import 'speech_text.dart';
import 'tts_client.dart';
import 'tts_config.dart';
import 'wav.dart';

/// What the companion voice is doing right now.
enum TtsPhase { idle, synthesizing, playing }

/// Snapshot of the voice: a phase plus the last failure, if any.
class TtsStatus {
  const TtsStatus({this.phase = TtsPhase.idle, this.error});

  final TtsPhase phase;

  /// Human readable failure for the panel to surface once, then cleared.
  final String? error;

  @override
  String toString() => 'TtsStatus($phase${error == null ? '' : ', $error'})';
}

/// Speaks assistant replies sentence by sentence.
///
/// The endpoint answers with a whole WAV, so a long reply would otherwise be
/// silent for seconds: the reply is split into sentences, each one is
/// synthesized and played in turn, and the next sentence is synthesized while
/// the current one plays. A new [speak] replaces whatever is in flight: the
/// user asked for the newest reply, not a queue of old ones.
class TtsService {
  TtsService({
    required this.client,
    required this.output,
    required this.config,
    required this.tempDirectory,
    Duration Function(Uint8List wav)? durationOf,
  }) : durationOf = durationOf ??
            ((wav) => Duration(milliseconds: wavDurationMs(wav)));

  final TtsClient client;
  final AudioOutput output;
  final TtsConfig Function() config;
  final Future<Directory> Function() tempDirectory;
  final Duration Function(Uint8List wav) durationOf;

  final StreamController<TtsStatus> _statuses =
      StreamController<TtsStatus>.broadcast();

  TtsStatus _status = const TtsStatus();
  int _generation = 0;
  int _failedGeneration = -1;
  Directory? _tempDir;
  File? _playingFile;

  Stream<TtsStatus> get statuses => _statuses.stream;

  TtsStatus get status => _status;

  /// Speaks [reply], replacing any line already playing or being synthesized.
  Future<void> speak(String reply) async {
    final settings = config();
    final chunks = _chunksFor(reply);
    await _halt();
    if (!settings.enabled || chunks.isEmpty) return;

    final generation = _generation;
    var pending = _synthesize(chunks.first, settings, generation);
    for (var index = 0; index < chunks.length; index++) {
      final wav = await pending;
      if (generation != _generation) return;
      if (wav == null) continue;
      if (index + 1 < chunks.length) {
        pending = _synthesize(chunks[index + 1], settings, generation);
      }
      await _play(wav, settings, generation);
      if (generation != _generation) return;
    }
    // Keep the failure visible until the next reply, so the panel can read it.
    if (_failedGeneration != generation) _emit(const TtsStatus());
  }

  /// Stops playback and drops the sentences that have not been spoken yet.
  Future<void> stop() => _halt();

  void dispose() {
    _generation++;
    output.dispose();
    _statuses.close();
  }

  Future<void> _halt() async {
    _generation++;
    await output.stop();
    final file = _playingFile;
    _playingFile = null;
    if (file != null) await _deleteQuietly(file);
    if (_status.phase != TtsPhase.idle || _status.error != null) {
      _emit(const TtsStatus());
    }
  }

  Future<Uint8List?> _synthesize(
    String chunk,
    TtsConfig settings,
    int generation,
  ) async {
    final safe = ttsSafe(chunk);
    if (safe.isEmpty) return null;
    _emit(const TtsStatus(phase: TtsPhase.synthesizing));
    try {
      return await client.synthesize(
        safe,
        voice: settings.voice,
        speed: settings.speed,
      );
    } on TtsException catch (error) {
      // Punctuation sometimes trips the engine; retry once without it.
      final plain = ttsPlain(chunk);
      if (plain.isNotEmpty && plain != safe) {
        try {
          return await client.synthesize(
            plain,
            voice: settings.voice,
            speed: settings.speed,
          );
        } on TtsException catch (retry) {
          _fail(retry.message, generation);
          return null;
        }
      }
      _fail(error.message, generation);
      return null;
    }
  }

  Future<void> _play(Uint8List wav, TtsConfig settings, int generation) async {
    final bytes = applyGain(wav, settings.volume);
    final file = await _writeTemp(bytes);
    if (generation != _generation) {
      await _deleteQuietly(file);
      return;
    }
    _playingFile = file;
    _emit(const TtsStatus(phase: TtsPhase.playing));
    try {
      await output.playFile(file.path);
    } on TtsPlaybackException catch (error) {
      _fail(error.message, generation);
      await _deleteQuietly(file);
      return;
    }
    final length = durationOf(wav);
    await Future<void>.delayed(
      length <= Duration.zero ? const Duration(milliseconds: 800) : length,
    );
    await _deleteQuietly(file);
    if (_playingFile == file) _playingFile = null;
  }

  Future<File> _writeTemp(Uint8List bytes) async {
    final dir = _tempDir ??= await tempDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'line_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A file still held by the player is cleaned up on the next run.
    }
  }

  List<String> _chunksFor(String reply) {
    final spoken = speechText(reply);
    if (spoken.isEmpty) return const [];
    return splitSpeech(spoken)
        .where((chunk) => ttsSafe(chunk).isNotEmpty)
        .toList(growable: false);
  }

  void _fail(String message, int generation) {
    if (generation != _generation) return;
    _failedGeneration = generation;
    _emit(TtsStatus(error: message));
  }

  void _emit(TtsStatus status) {
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }
}
