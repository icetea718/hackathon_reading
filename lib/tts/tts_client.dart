import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tts_config.dart';
import 'wav.dart';

/// Failure while talking to the speech service.
class TtsException implements Exception {
  const TtsException(this.message, {this.statusCode});

  final String message;

  /// HTTP status when the failure came from a response, null for transport
  /// errors.
  final int? statusCode;

  @override
  String toString() => message;
}

/// Synthesizes speech for one chunk of text.
abstract class TtsClient {
  /// Returns a complete WAV buffer for [text].
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  });

  /// Whether the service is up and its model loaded.
  Future<bool> ping();

  void dispose();
}

/// Talks to a GPT-SoVITS `api_v2` server over its OpenAI-shaped endpoint.
class OpenAiTtsClient implements TtsClient {
  OpenAiTtsClient({required this.config, HttpClient? httpClient})
      : _http = httpClient ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 10);
  }

  /// Live snapshot of the settings; the client is long-lived.
  final TtsConfig Function() config;

  final HttpClient _http;

  /// One sentence may take a while on CPU; the plugin allows two minutes.
  static const Duration _synthesisTimeout = Duration(seconds: 120);
  static const Duration _pingTimeout = Duration(seconds: 5);

  @override
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  }) async {
    final settings = config();
    final base = settings.baseUrl.trim();
    if (base.isEmpty) {
      throw const TtsException('未配置语音服务');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const TtsException('没有可朗读的文字');
    }

    final uri = _endpoint(base, 'audio/speech');
    final payload = jsonEncode({
      'model': 'gpt-sovits',
      'input': trimmed,
      'voice': voice,
      'speed': speed,
      'response_format': 'wav',
    });

    try {
      final request = await _http.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'audio/wav');
      request.add(utf8.encode(payload));
      final response = await request.close().timeout(_synthesisTimeout);
      final bytes = await _readBytes(response).timeout(_synthesisTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw TtsException(
          'HTTP ${response.statusCode}: ${_snippet(bytes)}',
          statusCode: response.statusCode,
        );
      }
      if (tryParseWavHeader(bytes) == null) {
        throw TtsException(
          '返回的不是 WAV 音频: ${_snippet(bytes)}',
          statusCode: response.statusCode,
        );
      }
      return bytes;
    } on TtsException {
      rethrow;
    } on TimeoutException {
      throw const TtsException('合成超时');
    } on SocketException catch (error) {
      throw TtsException('无法连接语音服务: ${error.message}');
    } on HttpException catch (error) {
      throw TtsException('网络错误: ${error.message}');
    }
  }

  @override
  Future<bool> ping() async {
    final base = config().baseUrl.trim();
    if (base.isEmpty) return false;
    try {
      final request = await _http.getUrl(_endpoint(base, 'health'));
      final response = await request.close().timeout(_pingTimeout);
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } on Object {
      return false;
    }
  }

  @override
  void dispose() => _http.close(force: true);

  Uri _endpoint(String baseUrl, String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed/$path');
  }

  Future<Uint8List> _readBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String _snippet(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    return text.length <= 200 ? text : '${text.substring(0, 200)}…';
  }
}
