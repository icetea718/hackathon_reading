/// Chat message roles accepted by OpenAI-compatible endpoints.
enum LlmRole { system, user, assistant }

class LlmMessage {
  const LlmMessage(this.role, this.content);

  final LlmRole role;
  final String content;

  Map<String, Object?> toJson() => {
        'role': role.name,
        'content': content,
      };
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

  void dispose();
}
