import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Plays a WAV file from disk.
abstract class AudioOutput {
  /// Starts [path] and returns immediately; playback continues in the
  /// background until it ends or [stop] is called.
  Future<void> playFile(String path);

  /// Silences whatever is playing right now.
  Future<void> stop();

  void dispose();
}

/// Plays through `winmm.dll`'s `PlaySoundW`.
///
/// A Flutter audio plugin would need symlinked plugin directories, which the
/// build machine cannot create, so the Windows multimedia API is called
/// directly: `SND_ASYNC` returns at once, `SND_FILENAME` names the file and
/// `SND_NODEFAULT` forbids the system beep when the file is missing.
class WinmmAudioOutput implements AudioOutput {
  static const int _sndAsync = 0x0001;
  static const int _sndNoDefault = 0x0002;
  static const int _sndFilename = 0x00020000;

  static _PlaySoundDart? _playSound;

  static _PlaySoundDart _resolve() {
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

  @override
  Future<void> playFile(String path) async {
    final play = _resolve();
    final native = path.toNativeUtf16();
    try {
      final started = play(
        native,
        0,
        _sndAsync | _sndNoDefault | _sndFilename,
      );
      if (started == 0) {
        throw TtsPlaybackException('无法播放音频: $path');
      }
    } finally {
      calloc.free(native);
    }
  }

  @override
  Future<void> stop() async {
    final play = _resolve();
    play(nullptr, 0, 0);
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
  Future<void> playFile(String path) async {}

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
