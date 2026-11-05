/// Chat message roles accepted by OpenAI-compatible endpoints.
enum LlmRole { system, user, assistant, tool }

class LlmMessage {
  const LlmMessage(
    this.role,
    this.content, {
    this.toolCalls = const [],
    this.toolCallId,
  });

  final LlmRole role;
  final String content;

  /// Tool calls the assistant asked for in this message.
  final List<LlmToolCall> toolCalls;

  /// Links a [LlmRole.tool] answer back to the call it answers.
  final String? toolCallId;

  Map<String, Object?> toJson() => {
        'role': role.name,
        'content': content,
        if (toolCalls.isNotEmpty)
          'tool_calls': [for (final call in toolCalls) call.toJson()],
        if (toolCallId != null) 'tool_call_id': toolCallId,
      };
}

/// One function call the model asked for.
class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;

  /// Raw JSON text as the model produced it; may be malformed.
  final String arguments;

  Map<String, Object?> toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
      };
}

/// A tool the model is allowed to call, in the wire shape it expects.
class LlmToolSpec {
  const LlmToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// Result of one non-streaming turn: prose, tool calls, or both.
class LlmTurn {
  const LlmTurn({this.content = '', this.toolCalls = const []});

  final String content;
  final List<LlmToolCall> toolCalls;

  bool get wantsTools => toolCalls.isNotEmpty;
}

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode});

  final String message;

  /// HTTP status when the failure came from the transport, null otherwise.
  final int? statusCode;

  @override
  String toString() => message;
}

/// Cooperative cancellation shared by the client and the pipeline.
class CancelToken {
  final Set<void Function()> _listeners = {};
  bool _isCanceled = false;

  bool get isCanceled => _isCanceled;

  void addListener(void Function() listener) {
    if (_isCanceled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_isCanceled) return;
    _isCanceled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

abstract class LlmClient {
  /// Streams assistant content deltas.
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  });

  /// Sends one non-streaming request and returns the full message content.
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  });

  /// One non-streaming turn that may carry tool calls.
  ///
  /// Optional: clients that predate tool calling keep working, they just
  /// cannot be used for the tool loop.
  Future<LlmTurn> completeTurn(
    List<LlmMessage> messages, {
    List<LlmToolSpec>? tools,
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) =>
      throw UnsupportedError('completeTurn 未实现');

  void dispose();
}
