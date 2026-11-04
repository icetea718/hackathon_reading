import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'illustration_models.dart';

/// 调用火山方舟 Ark 的 `/images/generations` 接口。
///
/// 草图是文生图；上色是图生图：把草图 PNG 编码成 data URL 放进
/// `image` 字段。和 Python 版的行为保持一致。
class ArkImageClient {
  ArkImageClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.size = '1152x1536',
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 30);
  }

  final String baseUrl;
  final String apiKey;
  final String model;
  final String size;
  final HttpClient _httpClient;

  static const _timeout = Duration(seconds: 180);

  Future<Uint8List> generate({
    required String prompt,
    Uint8List? referenceImage,
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw IllustrationException('绘图提示词为空。');
    }
    if (baseUrl.trim().isEmpty) {
      throw IllustrationException('没有配置插画接口地址。');
    }
    if (apiKey.trim().isEmpty) {
      throw IllustrationException('没有配置插画 API Key。');
    }

    final payload = <String, Object?>{
      'model': model,
      'prompt': trimmedPrompt,
      'size': size,
      'watermark': false,
      if (referenceImage != null)
        'image': <String>[
          'data:image/png;base64,${base64Encode(referenceImage)}',
        ],
    };

    try {
      final request = await _httpClient
          .postUrl(_endpoint())
          .timeout(const Duration(seconds: 30));
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${apiKey.trim()}',
      );
      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw IllustrationException(
          '绘图接口返回 ${_describeError(response.statusCode, body)}',
        );
      }

      final object = jsonDecode(body);
      if (object is! Map) {
        throw IllustrationException('绘图接口返回格式异常。');
      }
      final data = object['data'];
      if (data is! List || data.isEmpty) {
        throw IllustrationException('绘图接口没有返回图片。');
      }
      final first = data.first;
      if (first is! Map) {
        throw IllustrationException('绘图接口返回格式异常。');
      }

      final url = first['url'];
      if (url is String && url.isNotEmpty) {
        return await _download(url);
      }
      final base64Body = first['b64_json'];
      if (base64Body is String && base64Body.isNotEmpty) {
        return base64Decode(base64Body);
      }
      throw IllustrationException('绘图接口没有返回图片地址。');
    } on TimeoutException {
      throw IllustrationException('绘图请求超时，请稍后重试。');
    } on SocketException catch (error) {
      throw IllustrationException('连接绘图服务失败：${error.message}');
    } on HttpException catch (error) {
      throw IllustrationException('绘图请求失败：${error.message}');
    } on FormatException {
      throw IllustrationException('绘图接口返回了无法解析的内容。');
    }
  }

  Uri _endpoint() {
    final base = baseUrl.trim().endsWith('/')
        ? baseUrl.trim().substring(0, baseUrl.trim().length - 1)
        : baseUrl.trim();
    return Uri.parse('$base/images/generations');
  }

  Future<Uint8List> _download(String url) async {
    final request = await _httpClient
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw IllustrationException('下载图片失败：HTTP ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static String _describeError(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return 'HTTP $statusCode：${error['message']}';
        }
      }
    } on FormatException {
      // Fall through to the raw body.
    }
    final single = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.isEmpty) return 'HTTP $statusCode';
    final snippet = single.length <= 180 ? single : '${single.substring(0, 180)}…';
    return 'HTTP $statusCode：$snippet';
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}
