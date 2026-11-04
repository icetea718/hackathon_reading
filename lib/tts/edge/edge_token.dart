import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The clock-derived `Sec-MS-GEC` token the Edge read-aloud endpoint demands.
///
/// Microsoft replaced the v1 scheme (a bare SHA-256) in 2026-10: the handshake
/// now carries `Sec-MS-GEC-Version: 2-…` and the token is
/// `"<CS64 16 hex>-<SHA-256 64 hex>"`, built over a fixed copyright prefix
/// followed by `"<ticks><client token>"`.
///
/// Ported from `MsEdgeTTS.generateSecMsGec` (the vendored MIT copy under
/// `vendor/msedge-tts` of chino-tts, itself a port of rany2/edge-tts PR #492).
/// Every step is 32-bit arithmetic, so products go through [_mul32] instead of
/// Dart's 64-bit `*` — JS `Math.imul` keeps only the low 32 bits.
class EdgeToken {
  const EdgeToken._();

  /// The public client token every Edge read-aloud client ships.
  static const String clientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';

  /// Seconds between the Windows FILETIME epoch and the Unix epoch.
  static const int _winEpochOffset = 11644473600;

  /// SHA-256 of "Copyright (C) Microsoft Corporation. All rights reserved."
  /// is taken over this prefix; it is 57 bytes, not a multiple of four.
  static const int _prefixLength = 57;

  static const int _mask32 = 0xFFFFFFFF;

  /// The prefix as little-endian 32-bit words.
  static const List<int> _prefixWords = <int>[
    0x79706f43, 0x68676972, 0x43282074, 0x694d2029, 0x736f7263, 0x2074666f,
    0x70726f43, 0x7461726f, 0x2e6e6f69, 0x6c6c4120, 0x67697220, 0x20737468,
    0x65736572, 0x64657672, 0x0000002e,
  ];

  /// Token for the current clock, shifted by [clockOffset] when the server's
  /// `Date` header disagreed with this machine.
  static String generate({DateTime? now, Duration clockOffset = Duration.zero}) {
    final int millis = (now ?? DateTime.now()).millisecondsSinceEpoch +
        clockOffset.inMilliseconds;

    // 5-minute window, in 100 ns units since the Windows epoch.
    var ticks = millis ~/ 1000;
    ticks += _winEpochOffset;
    ticks -= ticks % 300;
    ticks *= 10000000;

    final List<int> suffix = utf8.encode('$ticks$clientToken');
    final Uint8List data = Uint8List(_prefixLength + suffix.length);
    final ByteData words = ByteData.sublistView(data);
    for (var i = 0; i < _prefixWords.length; i++) {
      words.setUint32(i * 4, _prefixWords[i], Endian.little);
    }
    data.setAll(_prefixLength, suffix);

    final List<int> digest = sha256.convert(data).bytes;
    final List<int> dataWords = _toWords(data);
    final List<int> digestWords = _toWords(Uint8List.fromList(digest));
    final int a = (digestWords[0] | 1) & _mask32;
    final int b = (digestWords[1] | 1) & _mask32;

    final List<int> swapped = _wordSwap(dataWords, a, b);
    final List<int> reversible = _reversible(dataWords, a, b);

    final ByteData cs64 = ByteData(8);
    cs64.setUint32(0, (swapped[0] ^ reversible[0]) & _mask32, Endian.little);
    cs64.setUint32(4, (swapped[1] ^ reversible[1]) & _mask32, Endian.little);

    return '${_hex(cs64.buffer.asUint8List())}-${_hex(digest)}';
  }

  /// Low 32 bits of `a * b`, the way [Math.imul] behaves.
  static int _mul32(int a, int b) {
    final int al = a & 0xFFFF;
    final int ah = (a >>> 16) & 0xFFFF;
    final int bl = b & 0xFFFF;
    final int bh = (b >>> 16) & 0xFFFF;
    final int mid = al * bh + ah * bl;
    return (al * bl + (mid << 16)) & _mask32;
  }

  /// Swap the halves of [x] after truncating it to 32 bits.
  static int _rol16(int x) {
    final int v = x & _mask32;
    return (((v << 16) & _mask32) | (v >>> 16)) & _mask32;
  }

  /// Little-endian 32-bit words, zero-padded to an 8-byte boundary.
  static List<int> _toWords(Uint8List bytes) {
    final int padded = ((bytes.length + 7) ~/ 8) * 8;
    final Uint8List buffer = Uint8List(padded)..setAll(0, bytes);
    final ByteData view = ByteData.sublistView(buffer);
    return List<int>.generate(
      padded ~/ 4,
      (int i) => view.getUint32(i * 4, Endian.little),
    );
  }

  /// First pass: a word swap chain over the data words.
  static List<int> _wordSwap(List<int> words, int a, int b) {
    var acc = 0;
    var last = 0;
    for (var i = 0; i < words.length; i += 2) {
      final int x = words[i];
      final int y = words[i + 1];
      var t = _rol16((_mul32(_rol16(x), 0xef0569fb) + _mul32(x, a)) & _mask32);
      var q = _mul32(t, 0x76f50f34);
      acc = (acc + _mul32(_rol16(q), 0xc3efea97) + q) & _mask32;
      t = _rol16((_mul32(_rol16(y), 0xc31713db) + _mul32(y, b)) & _mask32);
      q = _mul32(t, 0x1881ce3c);
      last = (_mul32(_rol16(q), 0x35bd1ec9) + q) & _mask32;
      acc = (acc + last) & _mask32;
    }
    return <int>[last, acc];
  }

  /// Second pass: a reversible state chain.
  static List<int> _reversible(List<int> words, int a, int b) {
    const List<int> rounds = <int>[
      0xcf98b111,
      0x87085b9f,
      0x12ceb96d,
      0x257e1d83,
    ];
    var state = 0;
    var acc = 0;
    for (var i = 0; i < words.length; i += 2) {
      state = _mul32((state + words[i]) & _mask32, a);
      for (final int round in rounds) {
        state = _mul32(_rol16(state), round);
      }
      var t = _mul32((words[i + 1] + state) & _mask32, b);
      t = _mul32(_rol16(t), 0xa27416f5);
      t = _rol16(_mul32(_rol16(t), 0xd38396ff));
      acc = (acc + state) & _mask32;
      state = _mul32(_rol16(_mul32(t, 0x7c932b89)), 0xbfa49f69);
      acc = (acc + state) & _mask32;
    }
    return <int>[state, acc];
  }

  static String _hex(List<int> bytes) => bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
