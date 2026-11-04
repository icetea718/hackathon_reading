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

/// Speaks assistant replies chunk by chunk.
///
/// The endpoint answers with a whole audio file, so a long reply would otherwise
/// be silent for seconds: the reply is split into chunks, each one is
/// synthesized and played in turn, and the following ones are synthesized while
/// the current one plays. A new [speak] replaces whatever is in flight: the user
/// asked for the newest reply, not a queue of old ones.
class TtsService {
  TtsService({
    required this.client,
    required this.output,
    required this.config,
    required this.tempDirectory,
    Duration Function(Uint8List wav)? durationOf,
  }) : durationOf = durationOf ??
            ((wav) => Duration(milliseconds: wavDurationMs(wav)));

  /// Requests kept in flight so a slow engine does not starve the speaker.
  ///
  /// A local clone engine runs several times slower than real time; with a
  /// single request in flight every sentence is followed by a long stall, which
  /// is exactly the "gasps for air" the reader was doing.
  static const int _prefetch = 2;

  /// Silence left between two lines once the engine padding is trimmed.
  ///
  /// The player needs a beat to release the previous file; anything longer is
  /// audible as a seam between two sentences of the same reply.
  static const Duration _lineGap = Duration(milliseconds: 20);

  /// Characters per request once the first sentence is already playing.
  ///
  /// A line costs one request and one player start, and the seam is audible
  /// whatever the engine does, so ask for as much text as the engine can turn
  /// around in the time the previous line plays. The first sentence is always
  /// sent alone, so the reply still starts within a second.
  static const int _mergeChars = 150;

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
  ///
  /// Every call speaks: whether a finished reply is read out on its own is the
  /// caller's decision ([TtsConfig.autoSpeak]), so a tap on a speaker icon and
  /// the companion's own lines are never silenced by a switch.
  Future<void> speak(String reply) async {
    final settings = config();
    final chunks = _chunksFor(reply);
    await _halt();
    if (chunks.isEmpty) return;

    final generation = _generation;
    final pending = <Future<Uint8List?>>[];
    var next = 0;

    void fill() {
      while (pending.length < _prefetch && next < chunks.length) {
        pending.add(_synthesize(chunks[next++], settings, generation));
      }
    }

    fill();
    while (pending.isNotEmpty) {
      final audio = await pending.removeAt(0);
      fill();
      if (generation != _generation) return;
      if (audio == null) continue;
      await _play(audio, settings, generation);
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

  Future<void> _play(Uint8List audio, TtsConfig settings, int generation) async {
    // Engines pad every clip with silence; playing that padding and then the
    // stall of the next request is what made the reader gasp.
    final trimmed = trimSilence(audio);
    final bytes = applyGain(trimmed, settings.volume);
    final extension =
        sniffAudioFormat(bytes) == AudioFormat.mp3 ? '.mp3' : '.wav';
    final file = await _writeTemp(bytes, extension);
    if (generation != _generation) {
      await _deleteQuietly(file);
      return;
    }
    _playingFile = file;
    _emit(const TtsStatus(phase: TtsPhase.playing));

    final computed = extension == '.wav'
        ? durationOf(bytes)
        : Duration.zero;
    final length = computed > Duration.zero ? computed : null;
    try {
      // The output reports the end of the line; MP3 length is unknown here, so
      // the player is asked instead of guessing.
      await output.playFile(file.path, duration: length);
    } on TtsPlaybackException catch (error) {
      _fail(error.message, generation);
      await _deleteQuietly(file);
      if (_playingFile == file) _playingFile = null;
      return;
    }
    if (generation == _generation) {
      await Future<void>.delayed(_lineGap);
    }
    await _deleteQuietly(file);
    if (_playingFile == file) _playingFile = null;
  }

  Future<File> _writeTemp(Uint8List bytes, String extension) async {
    final dir = _tempDir ??= await tempDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'line_${DateTime.now().microsecondsSinceEpoch}$extension',
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
    return speechChunks(spoken, maxChars: _mergeChars)
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
