import 'dart:convert';

import 'package:chinese_codec/chinese_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/services/txt_decoder.dart';

void main() {
  test('decodes UTF-8 Chinese', () {
    final result = decodeTxtBytes(utf8.encode('第一章 开始'));
    expect(result.text, '第一章 开始');
    expect(result.encoding, 'utf-8');
  });

  test('decodes UTF-8 with BOM', () {
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('中文')];
    final result = decodeTxtBytes(bytes);
    expect(result.text, '中文');
    expect(result.encoding, 'utf-8');
  });

  test('decodes UTF-16 LE with BOM', () {
    final bytes = <int>[0xFF, 0xFE];
    for (final unit in '中文'.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add(unit >> 8);
    }
    final result = decodeTxtBytes(bytes);
    expect(result.text, '中文');
    expect(result.encoding, 'utf-16le');
  });

  test('decodes UTF-16 BE with BOM', () {
    final bytes = <int>[0xFE, 0xFF];
    for (final unit in '中文'.codeUnits) {
      bytes.add(unit >> 8);
      bytes.add(unit & 0xFF);
    }
    final result = decodeTxtBytes(bytes);
    expect(result.text, '中文');
    expect(result.encoding, 'utf-16be');
  });

  test('decodes GB18030 Chinese', () {
    final bytes = gb18030.encode('第一章 开始');
    final result = decodeTxtBytes(bytes);
    expect(result.text, '第一章 开始');
    expect(result.encoding, 'gb18030');
  });

  test('never throws on invalid bytes', () {
    final result = decodeTxtBytes([0xFF, 0xFF, 0x00, 0xD8]);
    expect(result.encoding, 'utf-8-lossy');
  });

  test('empty input returns empty UTF-8 text', () {
    final result = decodeTxtBytes([]);
    expect(result.text, '');
    expect(result.encoding, 'utf-8');
  });
}
