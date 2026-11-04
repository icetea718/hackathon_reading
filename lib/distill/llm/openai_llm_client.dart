import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'llm_client.dart';
import 'llm_config.dart';
import 'sse.dart';

/// Talks to any OpenAI-compatible chat-completions endpoint.
///
/// The config is read through [config] on every call so settings changes take
/// effect immediately without rebuilding the client.
class OpenAiLlmClient implements LlmClient {
  OpenAiLlmClient({
    required this.config,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 15);
  }

  /// Read on every call so settings changes apply immediately.
  final LlmConfig Function() config;
  final HttpClient _httpClient;

  static const _timeout = Duration(seconds: 30);

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    final settings = config();
    _requireConfigured(settings);

    HttpClientRequest? request;
    void abort() => request?.abort();
    cancel?.addListener(abort);

    try {
      request = await _httpClient.postUrl(_chatUri(settings.baseUrl));
      _writeRequest(
        request,
        settings: settings,
        messages: messages,
        stream: true,
        temperature: temperature,
        maxTokens: maxTokens,
      );

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        throw LlmException(
          'HTTP ${response.statusCode}: ${_snippet(body)}',
          statusCode: response.statusCode,
        );
      }

      final lines =
          response.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (cancel?.isCanceled ?? false) break;
        final payload = ssePayload(line);
        if (payload == null) continue;
        if (payload == '[DONE]') break;
        final delta = sseContentDelta(payload);
        if (delta != null && delta.isNotEmpty) yield delta;
      }
    } on HttpException {
      if (!(cancel?.isCanceled ?? false)) rethrow;
    } on SocketException {
      if (!(cancel?.isCanceled ?? false)) rethrow;
    } finally {
      cancel?.removeListener(abort);
    }
  }

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async {
    final settings = config();
    _requireConfigured(settings);

    HttpClientRequest? request;
    void abort() => request?.abort();
    cancel?.addListener(abort);

    try {
      final pending = () async {
        request = await _httpClient.postUrl(_chatUri(settings.baseUrl));
        _writeRequest(
          request!,
          settings: settings,
          messages: messages,
          stream: false,
          temperature: temperature,
          maxTokens: maxTokens,
        );

        final response = await request!.close();
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode != HttpStatus.ok) {
          throw LlmException(
            'HTTP ${response.statusCode}: ${_snippet(body)}',
            statusCode: response.statusCode,
          );
        }

        final content = _contentOf(body);
        if (content == null) {
          throw LlmException('返回格式异常: ${_snippet(body)}');
        }
        return content;
      }();

      return await pending.timeout(
        _timeout,
        onTimeout: () => throw LlmException('请求超时'),
      );
    } on HttpException {
      if (cancel?.isCanceled ?? false) {
        throw LlmException('已取消');
      }
      rethrow;
    } on SocketException catch (error) {
      if (cancel?.isCanceled ?? false) {
        throw LlmException('已取消');
      }
      throw LlmException('网络错误: ${error.message}');
    } finally {
      cancel?.removeListener(abort);
    }
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
  }

  void _writeRequest(
    HttpClientRequest request, {
    required LlmConfig settings,
    required List<LlmMessage> messages,
    required bool stream,
    double? temperature,
    int? maxTokens,
  }) {
    request.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    request.headers.set('authorization', 'Bearer ${settings.apiKey.trim()}');
    if (stream) {
      request.headers.set('accept', 'text/event-stream');
    }
    request.add(
      utf8.encode(
        jsonEncode({
          'model': settings.model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': stream,
          'temperature': temperature ?? settings.temperature,
          'max_tokens': ?maxTokens,
        }),
      ),
    );
  }

  static Uri _chatUri(String baseUrl) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed/chat/completions');
  }

  static void _requireConfigured(LlmConfig settings) {
    if (!settings.isConfigured) {
      throw LlmException('未配置 AI 服务');
    }
  }

  static String? _contentOf(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    return content is String ? content : null;
  }

  static String _snippet(String body) {
    final single = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length <= 200 ? single : '${single.substring(0, 200)}…';
  }
}
