import 'dart:convert';

/// Returns the payload after `data: `, or null for lines that are not data.
///
/// `[DONE]` is returned verbatim so callers can end the stream.
String? ssePayload(String line) {
  final trimmed = line.endsWith('\r')
      ? line.substring(0, line.length - 1)
      : line;
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith(':')) return null;
  if (!trimmed.startsWith('data:')) return null;

  var payload = trimmed.substring('data:'.length);
  if (payload.startsWith(' ')) payload = payload.substring(1);
  return payload;
}

/// Pulls `choices[0].delta.content` out of a streaming chunk.
///
/// Returns null for chunks that carry no text (role-only deltas, usage
/// reports, malformed JSON).
String? sseContentDelta(String payload) {
  if (payload.isEmpty || payload == '[DONE]') return null;
  Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final delta = first['delta'];
  if (delta is! Map) return null;
  final content = delta['content'];
  return content is String ? content : null;
}
