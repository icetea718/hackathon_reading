import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Plays an audio file from disk.
abstract class AudioOutput {
  /// Starts [path] and completes once the line has finished — or earlier when
  /// [stop] is called.
  ///
  /// [duration] is the exact length of the clip when the caller already knows
  /// it (16-bit PCM WAV); passing null makes the platform report the end of
  /// playback itself. Awaiting the end is what keeps the synthesizer and the
  /// speaker in step: the next chunk is never queued behind a stale line.
  Future<void> playFile(String path, {Duration? duration});

  /// Silences whatever is playing right now.
  Future<void> stop();

  void dispose();
}

/// Plays through `winmm.dll`.
///
/// A Flutter audio plugin would need symlinked plugin directories, which the
/// build machine cannot create, so the Windows multimedia API is called
/// directly. 16-bit PCM WAV goes through `PlaySoundW`: `SND_ASYNC` returns at
/// once, `SND_FILENAME` names the file and `SND_NODEFAULT` forbids the system
/// beep when the file is missing. Formats `PlaySoundW` refuses (MP3, which the
/// edge engine of chino-tts answers with) go through `mciSendStringW`, whose
/// `status ... mode` reports the real end of the line.
class WinmmAudioOutput implements AudioOutput {
  static const int _sndAsync = 0x0001;
  static const int _sndNoDefault = 0x0002;
  static const int _sndFilename = 0x00020000;

  /// Waited past the computed WAV length so the last samples are not cut.
  static const Duration _tailPadding = Duration(milliseconds: 60);

  /// How often an MCI line is asked whether it is still playing.
  static const Duration _mciPoll = Duration(milliseconds: 60);

  /// Upper bound on a single line, so a stuck device cannot hang the reader.
  static const Duration _mciLimit = Duration(minutes: 10);

  static _PlaySoundDart? _playSound;
  static _MciSendStringDart? _mciSendString;
  static int _aliasSeed = 0;

  /// Completed by [stop]; the pending line returns instead of waiting.
  Completer<void>? _interrupted;

  /// Open MCI device of the line being played.
  String? _alias;

  static _PlaySoundDart _resolvePlaySound() {
    final cached = _playSound;
    if (cached != null) return cached;
    if (!Platform.isWindows) {
      throw UnsupportedError('朗读目前只支持 Windows');
    }
    final library = DynamicLibrary.open('winmm.dll');
    return _playSound = library.lookupFunction<_PlaySoundNative, _PlaySoundDart>(
      'PlaySoundW',
    );
  }

  static _MciSendStringDart _resolveMci() {
    final cached = _mciSendString;
    if (cached != null) return cached;
    if (!Platform.isWindows) {
      throw UnsupportedError('朗读目前只支持 Windows');
    }
    final library = DynamicLibrary.open('winmm.dll');
    return _mciSendString =
        library.lookupFunction<_MciSendStringNative, _MciSendStringDart>(
          'mciSendStringW',
        );
  }

  @override
  Future<void> playFile(String path, {Duration? duration}) {
    if (duration == null) return _playWithMci(path);
    return _playWav(path, duration);
  }

  Future<void> _playWav(String path, Duration duration) async {
    final play = _resolvePlaySound();
    final native = path.toNativeUtf16();
    try {
      final started = play(native, 0, _sndAsync | _sndNoDefault | _sndFilename);
      if (started == 0) {
        throw TtsPlaybackException('无法播放音频: $path');
      }
    } finally {
      calloc.free(native);
    }

    final token = Completer<void>();
    _interrupted = token;
    try {
      await Future.any<void>([
        Future<void>.delayed(duration + _tailPadding),
        token.future,
      ]);
    } finally {
      if (identical(_interrupted, token)) _interrupted = null;
      if (!token.isCompleted) token.complete();
    }
  }

  Future<void> _playWithMci(String path) async {
    final mci = _resolveMci();
    final alias = 'dsh_tts_${_aliasSeed++}';
    final token = Completer<void>();
    _interrupted = token;
    _alias = alias;
    try {
      final opened = _open(mci, path, alias);
      if (opened != 0) {
        throw TtsPlaybackException('无法播放音频（MCI $opened）: $path');
      }
      final played = _call(mci, 'play $alias');
      if (played != 0) {
        throw TtsPlaybackException('无法播放音频（MCI $played）: $path');
      }
      final deadline = DateTime.now().add(_mciLimit);
      while (!token.isCompleted && DateTime.now().isBefore(deadline)) {
        await Future.any<void>([
          Future<void>.delayed(_mciPoll),
          token.future,
        ]);
        if (token.isCompleted || !_isPlaying(mci, alias)) break;
      }
    } finally {
      _call(mci, 'stop $alias');
      _call(mci, 'close $alias');
      if (identical(_interrupted, token)) _interrupted = null;
      if (identical(_alias, alias)) _alias = null;
      if (!token.isCompleted) token.complete();
    }
  }

  /// Opens [path] under [alias]; `mpegvideo` covers MP3, the bare form covers
  /// whatever the device guesses.
  int _open(_MciSendStringDart mci, String path, String alias) {
    final quoted = '"${path.replaceAll('"', '')}"';
    final typed = _call(mci, 'open $quoted type mpegvideo alias $alias');
    if (typed == 0) return 0;
    return _call(mci, 'open $quoted alias $alias');
  }

  bool _isPlaying(_MciSendStringDart mci, String alias) {
    final reply = calloc<Uint16>(64).cast<Utf16>();
    try {
      if (_callWith(mci, 'status $alias mode', reply, 64) != 0) return false;
      return reply.toDartString().trim().startsWith('playing');
    } finally {
      calloc.free(reply);
    }
  }

  int _call(_MciSendStringDart mci, String command) =>
      _callWith(mci, command, nullptr, 0);

  int _callWith(
    _MciSendStringDart mci,
    String command,
    Pointer<Utf16> reply,
    int replyChars,
  ) {
    final native = command.toNativeUtf16();
    try {
      return mci(native, reply, replyChars, 0);
    } finally {
      calloc.free(native);
    }
  }

  @override
  Future<void> stop() async {
    final token = _interrupted;
    if (token != null && !token.isCompleted) token.complete();

    final alias = _alias;
    if (alias != null) {
      final mci = _resolveMci();
      _call(mci, 'stop $alias');
      _call(mci, 'close $alias');
    }
    if (Platform.isWindows) {
      _resolvePlaySound().call(nullptr, 0, 0);
    }
  }

  @override
  void dispose() {
    if (!Platform.isWindows) return;
    _playSound?.call(nullptr, 0, 0);
  }
}

/// Playback failed, usually because the file vanished or the codec is missing.
class TtsPlaybackException implements Exception {
  const TtsPlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Discards audio; used on platforms without playback and in tests.
class NoopAudioOutput implements AudioOutput {
  @override
  Future<void> playFile(String path, {Duration? duration}) async {
    if (duration != null) await Future<void>.delayed(duration);
  }

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

typedef _PlaySoundNative = Int32 Function(
  Pointer<Utf16> sound,
  IntPtr module,
  Uint32 flags,
);
typedef _PlaySoundDart = int Function(
  Pointer<Utf16> sound,
  int module,
  int flags,
);

typedef _MciSendStringNative = Uint32 Function(
  Pointer<Utf16> command,
  Pointer<Utf16> reply,
  Uint32 replyChars,
  IntPtr callback,
);
typedef _MciSendStringDart = int Function(
  Pointer<Utf16> command,
  Pointer<Utf16> reply,
  int replyChars,
  int callback,
);
