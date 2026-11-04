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

/// What the "test voice" button reports after asking the service.
class TtsProbe {
  const TtsProbe({required this.ok, required this.message});

  final bool ok;

  /// One line for the user: what answered, which voices exist, what is wrong.
  final String message;

  @override
  String toString() => message;
}

/// Synthesizes speech for one chunk of text.
abstract class TtsClient {
  /// Returns a complete audio buffer (WAV or MP3) for [text].
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  });

  /// Asks the service how it is doing, with a message fit for a snackbar.
  Future<TtsProbe> probe();

  /// Whether the service is up and its model loaded.
  Future<bool> ping() async => (await probe()).ok;

  void dispose();
}

/// Talks to a local TTS server over its OpenAI-shaped speech endpoint.
///
/// Both GPT-SoVITS `api_v2` and chino-tts answer `POST /audio/speech`; chino-tts
/// also serves `/v1/audio/speech`, and its responses are WAV (VoxCPM clone) or
/// MP3 (edge voices), so the payload is sniffed instead of trusted.
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

  /// Paths a speech service may expose, most specific first.
  static const List<String> _speechPaths = ['v1/audio/speech', 'audio/speech'];

  /// Suffixes that are stripped when the user pastes a full endpoint.
  static const List<String> _endpointSuffixes = [
    '/v1/audio/speech',
    '/audio/speech',
    '/v1',
  ];

  @override
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  }) async {
    final settings = config();
    final root = _rootOf(settings.baseUrl);
    if (root.isEmpty) {
      throw const TtsException('未配置语音服务');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const TtsException('没有可朗读的文字');
    }

    final payload = jsonEncode({
      'model': 'gpt-sovits',
      'input': trimmed,
      'voice': voice,
      'speed': speed,
      'response_format': 'wav',
    });

    TtsException? notFound;
    for (final path in _speechPaths) {
      try {
        final audio = await _post(root, path, payload, voice);
        return audio;
      } on TtsException catch (error) {
        // Only a missing route is worth retrying; everything else is an answer.
        if (error.statusCode != HttpStatus.notFound) rethrow;
        notFound = error;
      }
    }
    throw notFound ?? const TtsException('语音服务没有可用的合成接口');
  }

  Future<Uint8List> _post(
    String root,
    String path,
    String payload,
    String voice,
  ) async {
    final uri = Uri.parse('$root/$path');
    try {
      final request = await _http.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'audio/*');
      request.add(utf8.encode(payload));
      final response = await request.close().timeout(_synthesisTimeout);
      final bytes = await _readBytes(response).timeout(_synthesisTimeout);
      final status = response.statusCode;
      if (status != HttpStatus.ok) {
        throw TtsException(
          'HTTP $status：${_hint(_errorText(bytes), voice)}',
          statusCode: status,
        );
      }
      if (bytes.isEmpty) {
        throw TtsException(
          '语音服务没有返回音频（音色 $voice）',
          statusCode: status,
        );
      }
      if (sniffAudioFormat(bytes) == AudioFormat.unknown) {
        throw TtsException(
          '返回的不是音频：${_snippet(bytes)}',
          statusCode: status,
        );
      }
      return bytes;
    } on TtsException {
      rethrow;
    } on TimeoutException {
      throw const TtsException('合成超时');
    } on SocketException catch (error) {
      throw TtsException('无法连接语音服务 $root: ${error.message}');
    } on HttpException catch (error) {
      throw TtsException('网络错误: ${error.message}');
    }
  }

  @override
  Future<TtsProbe> probe() async {
    final settings = config();
    final root = _rootOf(settings.baseUrl);
    if (root.isEmpty) {
      return const TtsProbe(ok: false, message: '还没有填写语音服务地址');
    }
    final candidates = ['$root/health', '$root/v1/health', '$root/voices'];
    Object? lastError;
    for (final url in candidates) {
      try {
        final request = await _http.getUrl(Uri.parse(url));
        final response = await request.close().timeout(_pingTimeout);
        final bytes = await _readBytes(response).timeout(_pingTimeout);
        if (response.statusCode == HttpStatus.ok) {
          return TtsProbe(
            ok: true,
            message: _describe(root, bytes, settings.voice),
          );
        }
        if (response.statusCode == HttpStatus.notFound) continue;
        return TtsProbe(
          ok: false,
          message:
              '语音服务返回 HTTP ${response.statusCode}：${_snippet(bytes)}',
        );
      } on SocketException catch (error) {
        return TtsProbe(
          ok: false,
          message: '连不上 $root（${error.message}）；先启动 chino-tts',
        );
      } on TimeoutException {
        return TtsProbe(ok: false, message: '连接 $root 超时');
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      return TtsProbe(ok: false, message: '检查 $root 失败：$lastError');
    }
    return TtsProbe(ok: false, message: '$root 上没有 /health，可能不是语音服务');
  }

  @override
  Future<bool> ping() async => (await probe()).ok;

  @override
  void dispose() => _http.close(force: true);

  /// The service root of whatever the user typed.
  ///
  /// Accepts `127.0.0.1:8766`, `http://127.0.0.1:8766/`,
  /// `http://127.0.0.1:8766/v1` and a full `.../audio/speech` endpoint, because
  /// all of them are things people paste.
  static String _rootOf(String baseUrl) {
    var root = baseUrl.trim();
    if (root.isEmpty) return '';
    if (!root.contains('://')) root = 'http://$root';
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    final lower = root.toLowerCase();
    for (final suffix in _endpointSuffixes) {
      if (lower.endsWith(suffix)) {
        root = root.substring(0, root.length - suffix.length);
        break;
      }
    }
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    return root;
  }

  String _describe(String root, Uint8List bytes, String voice) {
    String? service;
    String? fallback;
    final voices = <String>[];
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is Map) {
        final name = decoded['service'];
        if (name is String) service = name;
        final list = decoded['voices'];
        if (list is List) {
          for (final item in list) {
            if (item is String) voices.add(item);
          }
        }
        final defaultVoice = decoded['default'];
        if (defaultVoice is String) fallback = defaultVoice;
      }
    } on Object {
      // A /health that is not JSON still proves the service answers.
    }

    final buffer = StringBuffer('语音服务可用：${service ?? root}');
    if (service != null) buffer.write('（$root）');
    if (fallback != null) buffer.write('，默认音色 $fallback');
    if (voices.isNotEmpty && !voices.contains(voice)) {
      buffer.write('；没有音色「$voice」，可选 ${voices.join('、')}');
    }
    return buffer.toString();
  }

  /// Names the usual chino-tts failure instead of leaving a bare engine error.
  String _hint(String message, String voice) {
    if (message.contains('no audio data')) {
      return '$message；音色「$voice」没有合成出音频，换一个音色（如 zhino-clone）';
    }
    return message;
  }

  String _errorText(Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true).trim();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is String && error.isNotEmpty) return error;
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
      }
    } on Object {
      // Not JSON: the body itself is the message.
    }
    return _snippet(bytes);
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
