import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/chat_repository.dart';
import '../../distill/llm/llm_client.dart';
import '../../search/book_context.dart';
import '../../search/book_memory.dart';
import '../../search/book_toolbox.dart';
import '../../search/companion_selection.dart';
import '../../search/search_book.dart';
import '../../search/search_hit.dart';
import '../../search/search_step.dart';
import '../../search/tool_agent.dart';

/// A wider chapter map for the tool path: the model can afford every title
/// when it is able to fetch chapter text itself.
const int toolBriefChars = 3600;

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
  bool _starting = false;
  Future<void>? _loadFuture;

  @override
  ChatState build() {
    ref.onDispose(() => _disposed = true);
    if (threadKey == newThreadKey) return const ChatState();
    _loadFuture = _load(threadKey);
    return ChatState(threadId: threadKey);
  }

  Future<void> _load(String threadId) async {
    final rows = await ref.read(chatMessageRepositoryProvider).list(threadId);
    if (_disposed) return;

    // The last answer's sources are all the transcript needs; earlier answers
    // keep their own hidden `sourcesJson` for a future per-message view.
    var hits = const <SearchHit>[];
    for (final row in rows.reversed) {
      if (row.role != 'assistant') continue;
      if (row.sourcesJson != null && row.sourcesJson!.trim().isNotEmpty) {
        try {
          hits = SearchHit.listFromJson(row.sourcesJson);
        } on Object {
          // Corrupt cached sources should not keep the history from opening.
        }
      }
      break;
    }
    state = state.copyWith(messages: rows, hits: hits);
  }

  Future<void> send(String text, {bool webSearch = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.streaming || _starting) return;

    _starting = true;
    try {
      await _loadFuture;
      if (_disposed) return;

      final messageRepo = ref.read(chatMessageRepositoryProvider);
      final threadRepo = ref.read(chatThreadRepositoryProvider);
      final bookId = ref.read(searchBookProvider);

      var threadId = state.threadId;
      var created = false;
      if (threadId == null) {
        final thread = await threadRepo.create(
          title: ChatThreadRepository.deriveTitle(trimmed),
          bookId: bookId,
        );
        threadId = thread.id;
        created = true;
      }
      if (_disposed) {
        if (created) await threadRepo.delete(threadId);
        return;
      }

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
      if (_disposed) {
        await messageRepo.updateContent(
          assistantRow.id,
          '',
          status: 'interrupted',
        );
        return;
      }

      final cancel = CancelToken();
      _cancel = cancel;
      state = state.copyWith(
        threadId: threadId,
        messages: [...before, userRow, assistantRow],
        streaming: true,
        searching: webSearch || bookId != null,
        clearError: true,
        hits: const [],
        degraded: false,
      );

      await _stream(
        threadId: threadId,
        userText: trimmed,
        assistantId: assistantRow.id,
        history: _history(before),
        webSearch: webSearch,
        bookId: bookId,
        cancel: cancel,
      );
    } catch (error) {
      if (!_disposed) {
        _cancel?.cancel();
        _cancel = null;
        state = state.copyWith(
          streaming: false,
          searching: false,
          error: _describe(error),
        );
      }
    } finally {
      _starting = false;
    }
  }

  /// Re-runs the last question without adding a second user turn.
  Future<void> retry({bool webSearch = false}) async {
    if (state.streaming || _starting) return;

    _starting = true;
    try {
      await _loadFuture;
      if (_disposed) return;

      final rows = state.messages;
      final userIndex = rows.lastIndexWhere((row) => row.role == 'user');
      if (userIndex < 0) return;

      final userRow = rows[userIndex];
      var assistantIndex = -1;
      for (var i = userIndex + 1; i < rows.length; i++) {
        if (rows[i].role == 'assistant') {
          assistantIndex = i;
          break;
        }
      }
      if (assistantIndex < 0) {
        _starting = false;
        await send(userRow.content, webSearch: webSearch);
        return;
      }

      final messageRepo = ref.read(chatMessageRepositoryProvider);
      final assistantRow = rows[assistantIndex];
      final bookId = ref.read(searchBookProvider);
      final cancel = CancelToken();
      _cancel = cancel;

      try {
        await messageRepo.updateContent(
          assistantRow.id,
          '',
          status: 'streaming',
          clearSources: true,
        );
        // A retry can take a different path (tools off, no tools, degraded), so
        // the previous round's steps must not linger over the new answer.
        await messageRepo.updateSteps(assistantRow.id, null);
      } catch (error) {
        if (!_disposed) {
          _cancel = null;
          state = state.copyWith(
            streaming: false,
            searching: false,
            error: _describe(error),
          );
        }
        return;
      }
      if (_disposed) {
        await messageRepo.updateContent(
          assistantRow.id,
          '',
          status: 'interrupted',
        );
        return;
      }

      state = state.copyWith(
        streaming: true,
        searching: webSearch || bookId != null,
        clearError: true,
        hits: const [],
        degraded: false,
        messages: [
          for (final row in rows)
            if (row.id == assistantRow.id)
              row.copyWith(
                content: '',
                status: 'streaming',
                sourcesJson: const Value<String?>(null),
                stepsJson: const Value<String?>(null),
              )
            else
              row,
        ],
      );

      await _stream(
        threadId: userRow.threadId,
        userText: userRow.content,
        assistantId: assistantRow.id,
        history: _history(rows.sublist(0, userIndex)),
        webSearch: webSearch,
        bookId: bookId,
        cancel: cancel,
      );
    } finally {
      _starting = false;
    }
  }

  /// Whether the book has searchable text at all: a still-importing book or a
  /// non-text format has nothing for the tools to read. The first few chapters
  /// are probed because a book may open with an empty cover/title chapter.
  Future<bool> _hasChapterText(String bookId) async {
    final chapters = ref.read(chapterRepositoryProvider);
    try {
      final summaries = await chapters.getSummariesForBook(bookId);
      final probe = summaries.isEmpty
          ? const [0]
          : summaries.take(3).map((chapter) => chapter.index).toList();
      for (final index in probe) {
        final text = await chapters.getContent(bookId, index);
        if (text != null && text.trim().isNotEmpty) return true;
      }
      return false;
    } on Object {
      return false;
    }
  }

  Future<void> _stream({
    required String threadId,
    required String userText,
    required String assistantId,
    required List<LlmMessage> history,
    required bool webSearch,
    required String? bookId,
    required CancelToken cancel,
  }) async {
    final messageRepo = ref.read(chatMessageRepositoryProvider);
    final threadRepo = ref.read(chatThreadRepositoryProvider);
    final store = ref.read(searchConfigStoreProvider);
    final buffer = StringBuffer();
    final steps = <SearchStep>[];
    var hits = const <SearchHit>[];
    var degraded = false;
    var failed = false;
    String? errorText;
    BookContext? bookContext;

    // Tool calling only pays off when there is text to search, and only when
    // the reader has not turned it off and this model has not refused it.
    var model = '';
    try {
      model = (await ref.read(llmConfigProvider.future)).model;
    } on Object {
      model = '';
    }
    var useTools = bookId != null &&
        await store.toolsEnabled() &&
        (model.isEmpty || !await store.isToolsUnsupported(model)) &&
        await _hasChapterText(bookId);

    if (!cancel.isCanceled && !_disposed && bookId != null) {
      try {
        bookContext = await ref.read(bookContextBuilderProvider).build(
              bookId,
              question: useTools ? '' : userText,
              includeExcerpts: !useTools,
              briefChars: useTools ? toolBriefChars : null,
            );
      } on Object {
        // A missing/broken book should not stop a model-only answer.
        bookContext = null;
      }
      if (bookContext == null) useTools = false;
    }

    BookMemory? memory;
    if (!cancel.isCanceled && !_disposed && bookId != null) {
      try {
        final selection = ref.read(companionSelectionProvider(bookId));
        memory = await ref
            .read(bookMemoryBuilderProvider)
            .build(bookId, threadIds: selection);
      } on Object {
        // The reader's notes are a bonus; never fail the answer over them.
        memory = null;
      }
    }

    if (!cancel.isCanceled && !_disposed && webSearch) {
      try {
        hits = await ref.read(webSearchProvider).search(userText, cancel: cancel);
        degraded = hits.isEmpty;
      } on Object {
        // Retrieval is best-effort: any provider failure degrades to the model,
        // but a user stop is not a failure and must not show the retry bar.
        if (!cancel.isCanceled && !_disposed) degraded = true;
      }
      if (!_disposed && !cancel.isCanceled) {
        state = state.copyWith(
          searching: false,
          hits: hits,
          degraded: degraded,
        );
      }
    } else if (!_disposed && !cancel.isCanceled) {
      state = state.copyWith(searching: false);
    }

    if (!cancel.isCanceled && !_disposed) {
      var lastFlushAt = DateTime.now();
      var lastFlushed = 0;

      Future<void> flush(String status) {
        lastFlushAt = DateTime.now();
        lastFlushed = buffer.length;
        return messageRepo.updateContent(
          assistantId,
          buffer.toString(),
          status: status,
        );
      }

      Future<void> persistSteps() async {
        try {
          await messageRepo.updateSteps(
            assistantId,
            SearchStep.listToJson(steps),
          );
        } on Object {
          // Steps are decoration; a vanished thread must not fail the answer.
        }
      }

      Future<void> streamClassic() async {
        final agent = ref.read(agentServiceProvider);
        await for (final chunk in agent.send(
          history: history,
          userText: userText,
          hits: hits,
          book: bookContext,
          memory: memory,
          cancel: cancel,
        )) {
          if (cancel.isCanceled || _disposed) break;
          buffer.write(chunk);
          _patchAssistant(assistantId, buffer.toString());
          final due = DateTime.now().difference(lastFlushAt) >= flushInterval;
          if (due || buffer.length - lastFlushed >= flushBytes) {
            await flush('streaming');
            if (_disposed) break;
          }
        }
      }

      try {
        if (useTools && bookContext != null && bookId != null) {
          final toolAgent = ref.read(searchToolAgentProvider);
          try {
            await toolAgent.run(
              history: history,
              userText: userText,
              book: bookContext,
              toolbox: BookToolbox(
                book: bookContext,
                searcher: ref.read(bookSearcherProvider),
              ),
              memory: memory,
              hits: hits,
              cancel: cancel,
              onText: (delta) {
                if (cancel.isCanceled || _disposed) return;
                buffer.write(delta);
                _patchAssistant(assistantId, buffer.toString());
                final due =
                    DateTime.now().difference(lastFlushAt) >= flushInterval;
                if (due || buffer.length - lastFlushed >= flushBytes) {
                  unawaited(flush('streaming'));
                }
              },
              onStep: (step) {
                steps.add(step);
                _patchSteps(assistantId, steps);
                unawaited(persistSteps());
              },
            );
          } on ToolUnsupportedException {
            // The endpoint refused `tools`: answer the classic way and stop
            // offering the loop for this model until it changes.
            if (model.isNotEmpty) {
              try {
                await store.markToolsUnsupported(model);
              } on Object {
                // A settings write is best-effort.
              }
            }
            steps.add(
              const SearchStep(
                tool: 'notice',
                summary: '当前模型不支持工具检索，已用摘要回答',
                chapters: [],
                hits: 0,
                ms: 0,
              ),
            );
            await persistSteps();
            try {
              bookContext = await ref
                  .read(bookContextBuilderProvider)
                  .build(bookId, question: userText);
            } on Object {
              bookContext = null;
            }
            if (!cancel.isCanceled && !_disposed) await streamClassic();
          }
        } else {
          await streamClassic();
        }
      } catch (error) {
        if (!cancel.isCanceled && !_disposed) {
          failed = true;
          errorText = _describe(error);
        }
      }
    }

    final status = (cancel.isCanceled || _disposed)
        ? 'interrupted'
        : failed
            ? 'failed'
            : 'complete';
    final sourcesJson = hits.isEmpty ? null : SearchHit.listToJson(hits);
    final stepsJson = steps.isEmpty ? null : SearchStep.listToJson(steps);

    try {
      await messageRepo.updateContent(
        assistantId,
        buffer.toString(),
        status: status,
        sourcesJson: sourcesJson,
        stepsJson: stepsJson,
      );
    } on Object {
      // The row can only vanish if the thread was deleted mid-answer.
    }
    try {
      await threadRepo.touch(threadId);
    } on Object {
      // The thread can only vanish with the row.
    }
    if (_disposed) return;

    _cancel = null;
    state = state.copyWith(
      streaming: false,
      searching: false,
      error: errorText,
      clearError: errorText == null,
      messages: [
        for (final row in state.messages)
          if (row.id == assistantId)
            row.copyWith(
              content: buffer.toString(),
              status: status,
              sourcesJson: Value(sourcesJson),
              stepsJson: Value(stepsJson),
            )
          else
            row,
      ],
    );
  }

  /// Stops the stream; whatever arrived is kept as an interrupted reply.
  void stop() {
    _cancel?.cancel();
  }

  /// Clears the draft conversation, for a scope switch or a new conversation.
  /// Unlike invalidating the provider this keeps the instance alive, so the
  /// composer's live lookup still reaches a usable controller.
  void reset() {
    _cancel?.cancel();
    _cancel = null;
    _starting = false;
    state = const ChatState();
  }

  void _patchAssistant(String id, String content) {
    state = state.copyWith(
      messages: [
        for (final row in state.messages)
          if (row.id == id) row.copyWith(content: content) else row,
      ],
    );
  }

  /// Shows a step as soon as it lands: the reader should see the book being
  /// searched, not a blank bubble that suddenly fills with an answer.
  void _patchSteps(String id, List<SearchStep> steps) {
    final json = steps.isEmpty ? null : SearchStep.listToJson(steps);
    state = state.copyWith(
      messages: [
        for (final row in state.messages)
          if (row.id == id) row.copyWith(stepsJson: Value(json)) else row,
      ],
    );
  }

  static List<LlmMessage> _history(List<ChatMessageRow> rows) => [
        for (final row in rows)
          if (row.content.trim().isNotEmpty)
            LlmMessage(
              row.role == 'assistant' ? LlmRole.assistant : LlmRole.user,
              row.content,
            ),
      ];

  static String _describe(Object error) {
    if (error is LlmException) return error.message;
    return '$error';
  }
}
