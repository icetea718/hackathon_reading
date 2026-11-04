import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/chat_repository.dart';
import '../../distill/llm/llm_client.dart';
import '../../search/book_context.dart';
import '../../search/search_book.dart';
import '../../search/search_hit.dart';
import '../../search/search_provider.dart';

/// Everything the 搜 shell needs to paint one conversation.
class ChatState {
  const ChatState({
    this.threadId,
    this.messages = const [],
    this.streaming = false,
    this.searching = false,
    this.error,
    this.hits = const [],
    this.degraded = false,
  });

  /// Null until the first question creates the row.
  final String? threadId;
  final List<ChatMessageRow> messages;

  /// A reply is being streamed right now.
  final bool streaming;

  /// Retrieval is in flight, before the first token.
  final bool searching;
  final String? error;

  /// Sources behind the current (or last) answer.
  final List<SearchHit> hits;

  /// Retrieval failed or came back empty; the answer is model-only.
  final bool degraded;

  ChatState copyWith({
    String? threadId,
    List<ChatMessageRow>? messages,
    bool? streaming,
    bool? searching,
    String? error,
    List<SearchHit>? hits,
    bool? degraded,
    bool clearError = false,
  }) {
    return ChatState(
      threadId: threadId ?? this.threadId,
      messages: messages ?? this.messages,
      streaming: streaming ?? this.streaming,
      searching: searching ?? this.searching,
      error: clearError ? null : (error ?? this.error),
      hits: hits ?? this.hits,
      degraded: degraded ?? this.degraded,
    );
  }
}

/// Drives one conversation: streaming, persistence, and cancellation.
///
/// Keyed by the thread id, or [newThreadKey] for a conversation that does not
/// exist in the database yet. The provider is not auto-disposed, so switching
/// to 阅 mid-answer and coming back keeps the stream alive.
class ChatController extends Notifier<ChatState> {
  ChatController(this.threadKey);

  /// A thread id, or [newThreadKey] before the first question.
  final String threadKey;

  static const String newThreadKey = 'new';
  static const Duration flushInterval = Duration(milliseconds: 300);
  static const int flushBytes = 2048;

  CancelToken? _cancel;
  bool _disposed = false;

  @override
  ChatState build() {
    ref.onDispose(() => _disposed = true);
    if (threadKey == newThreadKey) return const ChatState();
    unawaited(_load(threadKey));
    return ChatState(threadId: threadKey);
  }

  Future<void> _load(String threadId) async {
    final rows = await ref.read(chatMessageRepositoryProvider).list(threadId);
    if (_disposed) return;
    state = state.copyWith(messages: rows);
  }

  Future<void> send(String text, {bool webSearch = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.streaming) return;

    final messageRepo = ref.read(chatMessageRepositoryProvider);
    final threadRepo = ref.read(chatThreadRepositoryProvider);

    var threadId = state.threadId;
    if (threadId == null) {
      final thread = await threadRepo.create(
        title: ChatThreadRepository.deriveTitle(trimmed),
      );
      threadId = thread.id;
    }
    if (_disposed) return;

    final before = state.messages;
    final userRow = await messageRepo.append(
      threadId: threadId,
      role: 'user',
      content: trimmed,
    );
    final assistantRow = await messageRepo.append(
      threadId: threadId,
      role: 'assistant',
      content: '',
      status: 'streaming',
    );
    if (_disposed) return;

    final history = [
      for (final row in before)
        if (row.content.trim().isNotEmpty)
          LlmMessage(
            row.role == 'assistant' ? LlmRole.assistant : LlmRole.user,
            row.content,
          ),
    ];

    final cancel = CancelToken();
    _cancel = cancel;
    final bookId = ref.read(searchBookProvider);
    state = state.copyWith(
      threadId: threadId,
      messages: [...before, userRow, assistantRow],
      streaming: true,
      searching: webSearch || bookId != null,
      clearError: true,
      hits: const [],
      degraded: false,
    );

    BookContext? bookContext;
    if (bookId != null) {
      bookContext = await ref
          .read(bookContextBuilderProvider)
          .build(bookId, question: trimmed);
      if (_disposed) return;
    }

    var hits = const <SearchHit>[];
    var degraded = false;
    if (webSearch) {
      try {
        hits = await ref.read(webSearchProvider).search(trimmed, cancel: cancel);
        degraded = hits.isEmpty;
      } on SearchException {
        degraded = true;
      }
      if (_disposed) return;
      state = state.copyWith(
        searching: false,
        hits: hits,
        degraded: degraded,
      );
    }

    final buffer = StringBuffer();
    var lastFlushAt = DateTime.now();
    var lastFlushed = 0;

    Future<void> flush(String status) {
      lastFlushAt = DateTime.now();
      lastFlushed = buffer.length;
      return messageRepo.updateContent(
        assistantRow.id,
        buffer.toString(),
        status: status,
      );
    }

    var failed = false;
    try {
      final agent = ref.read(agentServiceProvider);
      await for (final chunk in agent.send(
        history: history,
        userText: trimmed,
        hits: hits,
        book: bookContext,
        cancel: cancel,
      )) {
        if (cancel.isCanceled || _disposed) break;
        buffer.write(chunk);
        _patchAssistant(assistantRow.id, buffer.toString());
        final due = DateTime.now().difference(lastFlushAt) >= flushInterval;
        if (due || buffer.length - lastFlushed >= flushBytes) {
          await flush('streaming');
          if (_disposed) return;
        }
      }
    } catch (error) {
      failed = true;
      if (!_disposed) {
        state = state.copyWith(error: _describe(error));
      }
    }

    final status = cancel.isCanceled || failed ? 'interrupted' : 'complete';
    final sourcesJson = hits.isEmpty ? null : SearchHit.listToJson(hits);
    try {
      await messageRepo.updateContent(
        assistantRow.id,
        buffer.toString(),
        status: status,
        sourcesJson: sourcesJson,
      );
    } on Object {
      // The row can only vanish if the thread was deleted mid-answer.
    }
    if (_disposed) return;

    _cancel = null;
    state = state.copyWith(
      streaming: false,
      searching: false,
      messages: [
        for (final row in state.messages)
          if (row.id == assistantRow.id)
            row.copyWith(content: buffer.toString(), status: status,
                sourcesJson: Value(sourcesJson))
          else
            row,
      ],
    );
  }

  /// Stops the stream; whatever arrived is kept as an interrupted reply.
  void stop() {
    _cancel?.cancel();
  }

  void _patchAssistant(String id, String content) {
    state = state.copyWith(
      messages: [
        for (final row in state.messages)
          if (row.id == id) row.copyWith(content: content) else row,
      ],
    );
  }

  static String _describe(Object error) {
    if (error is LlmException) return error.message;
    return '$error';
  }
}
