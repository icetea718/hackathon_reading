import 'dart:convert';
import 'dart:io';

/// A throwaway HTTP server that answers exactly one request per [handler].
///
/// Every request body is captured into [bodies] so a test can assert on what
/// the client actually sent.
class FakeLlmServer {
  FakeLlmServer._(this._server);

  final HttpServer _server;
  final List<HttpRequest> requests = [];
  final List<String> bodies = [];

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}/v1');

  static Future<FakeLlmServer> start(
    Future<void> Function(HttpRequest request, FakeLlmServer server) handler,
  ) async {
    final server = FakeLlmServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen((request) async {
      server.requests.add(request);
      server.bodies.add(await utf8.decoder.bind(request).join());
      await handler(request, server);
    });
    return server;
  }

  Future<void> stop() => _server.close(force: true);
}

Future<void> writeJson(HttpRequest request, Map<String, Object?> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> writeSse(HttpRequest request, List<String> lines) async {
  request.response.headers.set('content-type', 'text/event-stream');
  request.response.headers.set('cache-control', 'no-cache');
  for (final line in lines) {
    request.response.add(utf8.encode(line));
    await request.response.flush();
  }
  await request.response.close();
}
