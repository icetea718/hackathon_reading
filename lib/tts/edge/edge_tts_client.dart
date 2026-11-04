import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../tts_client.dart';
import '../tts_config.dart';
import 'edge_token.dart';
import 'edge_voices.dart';

/// Speaks through the Edge read-aloud endpoint Microsoft's own browser uses.
///
/// No local server, no node runtime, no model: one WebSocket per sentence, the
/// reply is MP3 (which the Windows player already handles through MCI). That is
/// what makes the default voice work on a machine where `chino-tts` was never
/// installed — and what turns "语音服务不可用" from a wall into a fallback.
class EdgeTtsClient implements TtsClient {
  EdgeTtsClient({
    required this.config,
    this.connectionTimeout = const Duration(seconds: 10),
    this.synthesisTimeout = const Duration(seconds: 30),
  });

  /// Live snapshot of the settings; rate and gain are prosody here, not samples.
  final TtsConfig Function() config;

  final Duration connectionTimeout;
  final Duration synthesisTimeout;

  static const String _endpoint =
      'wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1';

  /// 24 kHz mono MP3: small enough to send quickly, and `mciSendStringW` plays
  /// it without help.
  static const String _outputFormat = 'audio-24khz-48kbitrate-mono-mp3';

  /// Every frame carries text headers, then this, then the payload.
  static const String _delimiter = '\r\n\r\n';

  /// Binary frames put `Path:audio\r\n` before the MP3 bytes.
  static final List<int> _audioDelimiter = 'Path:audio\r\n'.codeUnits;

  /// The header set a real Edge tab sends. Akamai answers a bare handshake with
  /// a plain HTTP 200 instead of the 101 upgrade.
  static const Map<String, String> _browserHeaders = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0',
    'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Pragma': 'no-cache',
    'Cache-Control': 'no-cache',
    'Sec-CH-UA': '"Microsoft Edge";v="143", "Chromium";v="143", '
        '"Not A(Brand";v="24"',
    'Sec-CH-UA-Mobile': '?0',
    'Sec-CH-UA-Platform': '"Windows"',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'websocket',
    'Sec-Fetch-Site': 'none',
  };

  final Random _random = Random.secure();
  HttpClient? _http;

  @override
  Future<Uint8List> synthesize(
    String text, {
    required String voice,
    required double speed,
  }) async {
    final preset = EdgeVoices.resolve(voice);
    final spoken = _ssmlSafe(text);
    if (spoken.isEmpty) throw const TtsException('没有可朗读的文字');

    final settings = config();
    final socket = await _connect();
    final audio = BytesBuilder(copy: false);
    final requestId = _randomHex(16);
    final done = Completer<Uint8List>();

    final subscription = socket.listen(
      (dynamic frame) {
        if (frame is String) {
          if (frame.contains('Path:turn.end') && !done.isCompleted) {
            done.complete(audio.takeBytes());
          }
          return;
        }
        final bytes = frame as List<int>;
        final at = _indexOf(bytes, _audioDelimiter);
        if (at >= 0) audio.add(bytes.sublist(at + _audioDelimiter.length));
      },
      onError: (Object error) {
        if (!done.isCompleted) {
          done.completeError(TtsException('朗读连接出错：$error'));
        }
      },
      onDone: () {
        // turn.end never arrived: the clip would be cut off mid-sentence.
        if (!done.isCompleted) {
          done.completeError(
            const TtsException('朗读连接提前断开（没等到 turn.end），换个音色或重试'),
          );
        }
      },
    );

    try {
      socket.add(_configFrame);
      socket.add(_ssmlFrame(preset, spoken, requestId, speed, settings.volume));
      final bytes = await done.future.timeout(
        synthesisTimeout,
        onTimeout: () => throw TtsException(
          '微软朗读服务 ${synthesisTimeout.inSeconds} 秒内没有合成完',
        ),
      );
      if (bytes.isEmpty) {
        throw TtsException('音色「${preset.label}」没有合成出音频');
      }
      return bytes;
    } finally {
      // The clip is either finished or abandoned; either way the socket goes
      // away, and a peer that already dropped it is not an error worth raising.
      try {
        await subscription.cancel();
        await socket.close();
      } on Object {
        // nothing left to clean up
      }
    }
  }

  @override
  Future<TtsProbe> probe() async {
    final settings = config();
    final preset = EdgeVoices.resolve(settings.voice);
    final started = DateTime.now();
    try {
      final audio = await synthesize('你好，我在这儿。', voice: preset.id, speed: settings.speed);
      final spent = DateTime.now().difference(started).inMilliseconds;
      return TtsProbe(
        ok: true,
        message: '内置音色可用：${preset.label}（$spent ms，'
            '${(audio.length / 1024).round()} KB）；不需要本机 chino-tts',
      );
    } on TtsException catch (error) {
      return TtsProbe(
        ok: false,
        message: '内置音色不可用（${preset.label}）：${error.message}',
      );
    }
  }

  @override
  Future<bool> ping() async => (await probe()).ok;

  @override
  void dispose() {
    _http?.close(force: true);
    _http = null;
  }

  /// Text frame that tells the service which container to answer with.
  static String get _configFrame =>
      'Content-Type:application/json; charset=utf-8\r\nPath:speech.config$_delimiter'
      '{"context":{"synthesis":{"audio":{'
      '"metadataoptions":{"sentenceBoundaryEnabled":"false",'
      '"wordBoundaryEnabled":"false"},'
      '"outputFormat":"$_outputFormat"}}}}';

  /// The SSML request, with the voice's prosody pack merged into the sliders.
  String _ssmlFrame(
    EdgeVoice preset,
    String text,
    String requestId,
    double speed,
    double volume,
  ) {
    final rate = (preset.rate + (speed - 1) * 100).round();
    final gain = (preset.volume + (volume - 1) * 100)
        .round()
        .clamp(-100, 100)
        .toInt();
    final ssml = '<speak version="1.0" '
        'xmlns="http://www.w3.org/2001/10/synthesis" '
        'xmlns:mstts="https://www.w3.org/2001/mstts" '
        'xml:lang="${preset.locale}">'
        '<voice name="${preset.voice}">'
        '<prosody pitch="${_signed(preset.pitch)}Hz" '
        'rate="${_signed(rate)}%" volume="${_signed(gain)}%">'
        '$text'
        '</prosody></voice></speak>';
    return 'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'Path:ssml$_delimiter'
        '$ssml';
  }

  static String _signed(int value) => value >= 0 ? '+$value' : '$value';

  /// SSML is XML: the text has to be escaped, and one line, not paragraphs.
  static String _ssmlSafe(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// `flutter test` sets this variable; the mocked HTTP stack cannot upgrade a
  /// socket, and a real connection from every reader test would be noise.
  static bool get _runningInTests => Platform.environment['FLUTTER_TEST'] == 'true';

  Future<WebSocket> _connect() async {
    if (_runningInTests) {
      throw const TtsException('测试环境不发起联网朗读');
    }
    final token = EdgeToken.generate();
    final url = Uri.parse(
      '$_endpoint?Ocp-Apim-Subscription-Key=${EdgeToken.clientToken}'
      '&Sec-MS-GEC=$token'
      '&Sec-MS-GEC-Version=2-143.0.3650.75'
      '&ConnectionId=${_randomHex(16)}',
    );
    final http = _http ??= HttpClient()..connectionTimeout = connectionTimeout;
    // Honour HTTPS_PROXY when the machine only reaches the internet through one.
    http.findProxy = HttpClient.findProxyFromEnvironment;
    try {
      return await WebSocket.connect(
        url.toString(),
        headers: <String, Object>{
          ..._browserHeaders,
          'Cookie': 'muid=${_randomHex(16).toUpperCase()};',
        },
        customClient: http,
      ).timeout(connectionTimeout);
    } on TimeoutException {
      throw const TtsException('连接微软朗读服务超时（网络被拦？）');
    } on WebSocketException catch (error) {
      final message = error.message;
      if (message.contains('not upgraded')) {
        throw const TtsException('微软朗读接口拒绝了握手：网络被拦，或接口规则又变了');
      }
      throw TtsException('连不上微软朗读服务：$message');
    } on SocketException catch (error) {
      throw TtsException('连不上微软朗读服务：${error.message}');
    } catch (error) {
      // TLS handshake failures and mocked sockets are not SocketExceptions;
      // the caller only understands TtsException.
      throw TtsException('连不上微软朗读服务：$error');
    }
  }

  String _randomHex(int bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static int _indexOf(List<int> haystack, List<int> needle) {
    final limit = haystack.length - needle.length;
    for (var i = 0; i <= limit; i++) {
      var hit = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }
}
