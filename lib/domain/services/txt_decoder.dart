import 'dart:convert';
import 'dart:typed_data';

import 'package:chinese_codec/chinese_codec.dart';

import '../models/decoded_text.dart';

const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];
const List<int> _utf16LeBom = [0xFF, 0xFE];
const List<int> _utf16BeBom = [0xFE, 0xFF];

DecodedText decodeTxtBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    return const DecodedText(text: '', encoding: 'utf-8');
  }

  if (_startsWith(bytes, _utf8Bom)) {
    return DecodedText(
      text: utf8.decode(bytes.sublist(_utf8Bom.length)),
      encoding: 'utf-8',
    );
  }
  if (_startsWith(bytes, _utf16LeBom)) {
    return DecodedText(
      text: _decodeUtf16(bytes.sublist(_utf16LeBom.length), Endian.little),
      encoding: 'utf-16le',
    );
  }
  if (_startsWith(bytes, _utf16BeBom)) {
    return DecodedText(
      text: _decodeUtf16(bytes.sublist(_utf16BeBom.length), Endian.big),
      encoding: 'utf-16be',
    );
  }

  try {
    return DecodedText(text: utf8.decode(bytes), encoding: 'utf-8');
  } on FormatException {
    // Not UTF-8, try the legacy Chinese encodings below.
  }

  try {
    return DecodedText(text: gb18030.decode(bytes), encoding: 'gb18030');
  } on FormatException {
    // Neither strict UTF-8 nor GB18030; fall back to a lossy read.
  }

  return DecodedText(
    text: utf8.decode(bytes, allowMalformed: true),
    encoding: 'utf-8-lossy',
  );
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String _decodeUtf16(List<int> bytes, Endian endian) {
  final data = ByteData(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    data.setUint8(i, bytes[i]);
  }
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(data.getUint16(i, endian));
  }
  return String.fromCharCodes(units);
}
