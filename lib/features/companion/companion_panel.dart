import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../assistant/assistant_service.dart';
import '../../assistant/persona.dart';
import '../../assistant/reading_context.dart';
import '../../data/repositories/companion_chat_repository.dart';
import '../../domain/models/companion_chat.dart';
import '../../tts/tts_config.dart';
import '../../tts/tts_service.dart';
import '../settings/settings_page.dart';
import 'companion_history.dart';
import 'companion_memory_sheet.dart';
import 'companion_providers.dart';
import 'companion_quotes.dart';
import 'persona_mode_sheet.dart';

enum _CompanionView { chat, history }

/// Companion chat for the chapter the reader is looking at. Laid out as a
/// bottom sheet by default, or as a docked side column when [docked] is set.
class CompanionPanel extends ConsumerStatefulWidget {
  const CompanionPanel({
    super.key,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.chapterText,
    required this.chapterCharOffset,
    this.chapterPage,
    this.chapterPageEnd,
    this.chapterPageCount,
    this.bookPage,
    this.bookPageTotal,
    this.pageStartOffset,
    this.pageEndOffset,
    this.currentPageText = '',
    this.bookTitle = '',
    this.author = '',
    this.docked = false,
    this.onClose,
    this.onGoToChapter,
  });

  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final String chapterText;
  final int? chapterCharOffset;
  final int? chapterPage;
  final int? chapterPageEnd;
  final int? chapterPageCount;
  final int? bookPage;
  final int? bookPageTotal;
  final int? pageStartOffset;
  final int? pageEndOffset;
  final String currentPageText;
  final String bookTitle;
  final String author;

  /// Whether to fill the parent instead of sizing itself as a bottom sheet.
  final bool docked;

  /// Shown as a close button in the header when non-null.
  final VoidCallback? onClose;

  /// Called when the reader should follow a read-only thread to its chapter.
  final ValueChanged<int>? onGoToChapter;

  @override
  ConsumerState<CompanionPanel> createState() => _CompanionPanelState();
}

class _CompanionPanelState extends ConsumerState<CompanionPanel> {
  final List<ChatMessage> _history = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _streaming = '';
  bool _busy = false;
  bool _spoilerEnabled = false;
  String? _error;

  late final CompanionChatRepository _chats;
  CompanionThread? _thread;
  bool _autoTitlePending = false;
  int _requestToken = 0;

  _CompanionView _view = _CompanionView.chat;
  List<CompanionThread> _threads = const [];
  bool _threadsLoading = false;

  /// Thread from an earlier chapter being viewed; the composer is hidden.
  CompanionThread? _readOnlyThread;

  /// Thread to reopen once the reader lands on its chapter.
  String? _pendingThreadId;
  int? _pendingChapterIndex;

  /// Voice the reader just switched to, echoed into the transcript once.
  PersonaMode? _modeNotice;

  late final TtsService _tts;
  StreamSubscription<TtsStatus>? _ttsSubscription;
  TtsStatus _ttsStatus = const TtsStatus();

  /// History entry currently being spoken; null when nothing is playing.
  int? _speakingIndex;

  @override
  void initState() {
    super.initState();
    _chats = ref.read(companionChatRepositoryProvider);
    _tts = ref.read(ttsServiceProvider);
    _ttsSubscription = _tts.statuses.listen(_onTtsStatus);
    unawaited(_loadLatestThread());
  }

  @override
  void didUpdateWidget(covariant CompanionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId == widget.bookId &&
        oldWidget.chapterIndex == widget.chapterIndex) {
      return;
    }
    final pendingId = _pendingThreadId;
    final followPending = pendingId != null &&
        oldWidget.bookId == widget.bookId &&
        widget.chapterIndex == _pendingChapterIndex;
    _pendingThreadId = null;
    _pendingChapterIndex = null;
    _requestToken++;
    // Pending quotes belong to the chapter that was open; providers cannot be
    // modified inside didUpdateWidget, so drop them once the frame is done.
    if (ref.read(companionQuotesProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(companionQuotesProvider.notifier).clear();
      });
    }
    setState(() {
      _busy = false;
      _streaming = '';
      _error = null;
      _speakingIndex = null;
      _thread = null;
      _history.clear();
      _autoTitlePending = false;
      _view = _CompanionView.chat;
      _threads = const [];
      _threadsLoading = false;
      _readOnlyThread = null;
      _modeNotice = null;
    });
    unawaited(_tts.stop());
    if (followPending) {
      unawaited(_loadThreadById(pendingId));
    } else {
      unawaited(_loadLatestThread());
    }
  }

  Future<void> _loadThreadById(String id) async {
    final token = _requestToken;
    final thread = await _chats.threadById(id);
    if (thread == null) {
      if (mounted && token == _requestToken) await _loadLatestThread();
      return;
    }
    final messages = await _chats.messagesForThread(thread.id);
    if (!mounted || token != _requestToken) return;
    setState(() {
      _thread = thread;
      _history
        ..clear()
        ..addAll(messages.map(_toChatMessage));
      _autoTitlePending = false;
      _readOnlyThread = null;
    });
  }

  Future<void> _loadLatestThread() async {
    final token = _requestToken;
    final thread = await _chats.latestThreadForChapter(
      widget.bookId,
      widget.chapterIndex,
    );
    final messages = thread == null
        ? const <CompanionMessage>[]
        : await _chats.messagesForThread(thread.id);
    if (!mounted || token != _requestToken) return;
    setState(() {
      _thread = thread;
      _history
        ..clear()
        ..addAll(messages.map(_toChatMessage));
      _autoTitlePending = false;
    });
  }

  ChatMessage _toChatMessage(CompanionMessage message) {
    return ChatMessage(
      role: message.role == CompanionRole.user ? ChatRole.user : ChatRole.assistant,
      content: message.content,
    );
  }

  Future<void> _loadThreads() async {
    final bookId = widget.bookId;
    setState(() => _threadsLoading = true);
    final threads = await _chats.threadsForBook(bookId);
    if (!mounted || bookId != widget.bookId) return;
    setState(() {
      _threads = threads;
      _threadsLoading = false;
    });
  }

  void _selectTab(_CompanionView view) {
    if (_view == view) return;
    setState(() => _view = view);
    if (view == _CompanionView.history) {
      unawaited(_loadThreads());
    } else if (_readOnlyThread != null) {
      _readOnlyThread = null;
      unawaited(_reloadCurrentThread());
    }
  }

  Future<void> _reloadCurrentThread() async {
    final token = _requestToken;
    final thread = _thread;
    final messages = thread == null
        ? const <CompanionMessage>[]
        : await _chats.messagesForThread(thread.id);
    if (!mounted || token != _requestToken) return;
    setState(() {
      _history
        ..clear()
        ..addAll(messages.map(_toChatMessage));
      _error = null;
    });
  }

  void _cancelStream() {
    _requestToken++;
    setState(() {
      _busy = false;
      _streaming = '';
    });
  }

  Future<void> _newThread() async {
    if (_busy) _cancelStream();
    final thread = await _chats.createThread(
      bookId: widget.bookId,
      chapterIndex: widget.chapterIndex,
      chapterTitle: widget.chapterTitle,
      title: '新对话',
    );
    if (!mounted) return;
    setState(() {
      _thread = thread;
      _history.clear();
      _autoTitlePending = true;
      _error = null;
      _readOnlyThread = null;
      _view = _CompanionView.chat;
      _modeNotice = null;
    });
    unawaited(_loadThreads());
  }

  Future<void> _renameThread(CompanionThread thread, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await _chats.renameThread(thread.id, trimmed);
    if (!mounted) return;
    final current = _thread;
    final readOnly = _readOnlyThread;
    setState(() {
      if (current?.id == thread.id) {
        _thread = current!.copyWith(title: trimmed);
      }
      if (readOnly?.id == thread.id) {
        _readOnlyThread = readOnly!.copyWith(title: trimmed);
      }
    });
    unawaited(_loadThreads());
  }

  Future<void> _deleteThread(CompanionThread thread) async {
    final deletingCurrent = _thread?.id == thread.id;
    final deletingReadOnly = _readOnlyThread?.id == thread.id;
    if (deletingCurrent && _busy) _cancelStream();
    await _chats.deleteThread(thread.id);
    if (!mounted) return;

    if (deletingCurrent || deletingReadOnly) {
      final token = ++_requestToken;
      final latest = deletingCurrent
          ? await _chats.latestThreadForChapter(
              widget.bookId,
              widget.chapterIndex,
            )
          : _thread;
      final messages = latest == null
          ? const <CompanionMessage>[]
          : await _chats.messagesForThread(latest.id);
      if (!mounted || token != _requestToken) return;
      setState(() {
        _thread = latest;
        _history
          ..clear()
          ..addAll(messages.map(_toChatMessage));
        _autoTitlePending = false;
        _error = null;
        _readOnlyThread = null;
        _speakingIndex = null;
      });
    }
    unawaited(_loadThreads());
  }

  Future<void> _openThread(CompanionThread thread) async {
    if (_busy) _cancelStream();
    final token = _requestToken;
    final messages = await _chats.messagesForThread(thread.id);
    if (!mounted || token != _requestToken) return;
    final sameChapter = thread.chapterIndex == widget.chapterIndex;
    setState(() {
      _history
        ..clear()
        ..addAll(messages.map(_toChatMessage));
      if (sameChapter) {
        _thread = thread;
        _readOnlyThread = null;
      } else {
        _readOnlyThread = thread;
      }
      _autoTitlePending = false;
      _error = null;
      _view = _CompanionView.chat;
    });
  }

  Future<CompanionThread> _ensureThread({
    required String firstMessage,
    String? titleIfNew,
  }) async {
    final existing = _thread;
    if (existing != null) {
      if (_autoTitlePending) {
        _autoTitlePending = false;
        final title = companionThreadTitle(firstMessage);
        await _chats.renameThread(existing.id, title);
        final renamed = existing.copyWith(title: title);
        _thread = renamed;
        return renamed;
      }
      return existing;
    }
    final thread = await _chats.createThread(
      bookId: widget.bookId,
      chapterIndex: widget.chapterIndex,
      chapterTitle: widget.chapterTitle,
      title: titleIfNew ?? companionThreadTitle(firstMessage),
    );
    _thread = thread;
    return thread;
  }

  @override
  void dispose() {
    _ttsSubscription?.cancel();
    unawaited(_tts.stop());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTtsStatus(TtsStatus status) {
    if (!mounted) return;
    setState(() {
      _ttsStatus = status;
      if (status.phase == TtsPhase.idle) _speakingIndex = null;
    });
    final error = status.error;
    if (error != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _speak(String text, int? index) async {
    setState(() => _speakingIndex = index);
    await _tts.speak(text);
    if (mounted) setState(() => _speakingIndex = null);
  }

  void _hush() {
    setState(() => _speakingIndex = null);
    unawaited(_tts.stop());
  }

  ReadingContext get _context => ReadingContext(
        bookTitle: widget.bookTitle,
        author: widget.author,
        chapterTitle: widget.chapterTitle,
        chapterText: widget.chapterText,
        bookId: widget.bookId,
        chapterIndex: widget.chapterIndex,
        chapterCharOffset: widget.chapterCharOffset,
        chapterPage: widget.chapterPage,
        chapterPageEnd: widget.chapterPageEnd,
        chapterPageCount: widget.chapterPageCount,
        bookPage: widget.bookPage,
        bookPageTotal: widget.bookPageTotal,
        pageStartOffset: widget.pageStartOffset,
        pageEndOffset: widget.pageEndOffset,
        currentPageText: widget.currentPageText,
        allowSpoilers: _spoilerEnabled,
      );

  Future<void> _stream(
    Stream<String> Function(AssistantService service) start, {
    required int token,
    Future<void> Function(String reply)? onComplete,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _streaming = '';
    });
    try {
      final service = await ref.read(assistantServiceProvider.future);
      if (!mounted || token != _requestToken) return;
      if (!service.isConfigured) {
        setState(() => _error = '未配置 AI 服务，请到设置页填写');
        return;
      }
      final buffer = StringBuffer();
      await for (final chunk in start(service)) {
        buffer.write(chunk);
        if (!mounted || token != _requestToken) break;
        setState(() => _streaming = buffer.toString());
        _scrollToEnd();
      }
      if (!mounted || token != _requestToken) return;
      final reply = buffer.toString();
      if (reply.isNotEmpty) {
        await onComplete?.call(reply);
        if (!mounted || token != _requestToken) return;
      }
      setState(() {
        if (reply.isNotEmpty) {
          _history.add(
            ChatMessage(role: ChatRole.assistant, content: reply),
          );
        }
        _streaming = '';
      });
      if (reply.isNotEmpty) {
        unawaited(_speakIfAutoEnabled(reply, _history.length - 1));
      }
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = '出错了：$error';
        _streaming = '';
      });
    } finally {
      if (mounted && token == _requestToken) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || _readOnlyThread != null) return;
    final service = ref.read(assistantServiceProvider).value;
    if (service == null || !service.isConfigured) return;
    final quotes = ref.read(companionQuotesProvider).toList();
    final message = composeCompanionMessage(quotes, text);
    if (quotes.isNotEmpty) {
      ref.read(companionQuotesProvider.notifier).clear();
    }
    final persona = ref.read(personaModeProvider);
    _input.clear();
    final token = _requestToken;
    final thread = await _ensureThread(firstMessage: text);
    await _chats.appendMessage(
      threadId: thread.id,
      role: CompanionRole.user,
      content: message,
    );
    if (!mounted || token != _requestToken) return;
    setState(() {
      _history.add(ChatMessage(role: ChatRole.user, content: message));
      _modeNotice = null;
    });

    final priorCount = _history.length - 1;
    final start = priorCount > 8 ? priorCount - 8 : 0;
    final prior = _history.sublist(start, priorCount);
    final memory = await _chats.memoryDigest(
      bookId: widget.bookId,
      beforeChapterIndex: widget.chapterIndex,
    );
    if (!mounted || token != _requestToken) return;

    await _stream(
      (service) => service.chat(
        _context.copyWith(companionMemory: memory),
        prior,
        message,
        persona: persona,
      ),
      token: token,
      onComplete: (reply) => _chats.appendMessage(
        threadId: thread.id,
        role: CompanionRole.assistant,
        content: reply,
      ),
    );
  }

  Future<void> _summarize() async {
    if (_busy) return;
    final token = _requestToken;
    final thread = await _ensureThread(
      firstMessage: '总结本章',
      titleIfNew: '总结本章',
    );
    await _chats.appendMessage(
      threadId: thread.id,
      role: CompanionRole.user,
      content: '总结本章',
    );
    if (!mounted || token != _requestToken) return;
    setState(
      () => _history.add(
        const ChatMessage(role: ChatRole.user, content: '总结本章'),
      ),
    );
    final memory = await _chats.memoryDigest(
      bookId: widget.bookId,
      beforeChapterIndex: widget.chapterIndex,
    );
    if (!mounted || token != _requestToken) return;

    await _stream(
      // Summarising the chapter is an explicit request, so it may span the
      // whole chapter regardless of the spoiler switch.
      (service) => service.summarizeChapter(
        _context.copyWith(companionMemory: memory, allowSpoilers: true),
      ),
      token: token,
      onComplete: (reply) => _chats.appendMessage(
        threadId: thread.id,
        role: CompanionRole.assistant,
        content: reply,
      ),
    );
  }

  /// Enter sends the question, shift+enter keeps it for a second line, and
  /// enter that belongs to an input method (picking a character) stays with it.
  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter ||
        HardwareKeyboard.instance.isShiftPressed ||
        _input.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    unawaited(_send());
    return KeyEventResult.handled;
  }

  Future<void> _speakIfAutoEnabled(String text, int index) async {
    TtsConfig config;
    try {
      config = await ref.read(ttsConfigProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted || !config.autoSpeak) return;
    await _speak(text, index);
  }

  bool get _voiceOn => _ttsStatus.phase != TtsPhase.idle;

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(companionQuotesProvider, (previous, next) {
      if (next.length <= (previous?.length ?? 0)) return;
      final readOnly = _readOnlyThread;
      setState(() {
        _view = _CompanionView.chat;
        _readOnlyThread = null;
      });
      if (readOnly != null) unawaited(_loadLatestThread());
    });
    final quotes = ref.watch(companionQuotesProvider);
    final service = ref.watch(assistantServiceProvider);
    final configured = service is AsyncData<AssistantService> &&
        service.value.isConfigured;
    final loading = service is AsyncLoading<AssistantService>;

    final panel = Column(
      children: [
        _header(context, configured: configured),
        const Divider(height: 1),
        _tabs(context),
        if (_view == _CompanionView.history)
          Expanded(
            child: CompanionHistoryView(
              threads: _threads,
              currentChapterIndex: widget.chapterIndex,
              loading: _threadsLoading,
              onNewThread: () => unawaited(_newThread()),
              onOpen: (thread) => unawaited(_openThread(thread)),
              onRename: (thread, title) =>
                  unawaited(_renameThread(thread, title)),
              onDelete: (thread) => unawaited(_deleteThread(thread)),
            ),
          )
        else if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )
        else
          Expanded(
            child: _chatBody(
              context,
              configured: configured,
              quotes: quotes,
            ),
          ),
      ],
    );

    if (widget.docked) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        key: const Key('companion-docked'),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(left: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(left: false, child: panel),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: panel,
      ),
    );
  }

  Widget _header(BuildContext context, {required bool configured}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '陪读 · ${widget.chapterTitle}',
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_voiceOn)
            IconButton(
              key: const Key('companion-hush'),
              tooltip: '停止朗读',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _hush,
            ),
          IconButton(
            key: const Key('companion-memory'),
            tooltip: '回忆录',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: _openMemorySheet,
          ),
          TextButton(
            onPressed: configured && !_busy && _readOnlyThread == null
                ? _summarize
                : null,
            child: const Text('总结本章'),
          ),
          if (widget.onClose != null)
            IconButton(
              key: const Key('companion-close'),
              tooltip: '关闭陪读',
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _tabs(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String key, String label, _CompanionView value) {
      final selected = _view == value;
      return Expanded(
        child: TextButton(
          key: Key(key),
          onPressed: () => _selectTab(value),
          style: TextButton.styleFrom(
            foregroundColor:
                selected ? scheme.primary : scheme.onSurfaceVariant,
            shape: const RoundedRectangleBorder(),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('companion-tab-chat', '聊天', _CompanionView.chat),
        tab('companion-tab-history', '历史', _CompanionView.history),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 8),
          child: _ModePill(
            mode: ref.watch(personaModeProvider),
            onTap: () => unawaited(_openModeSheet()),
          ),
        ),
      ],
    );
  }

  Widget _chatBody(
    BuildContext context, {
    required bool configured,
    required List<String> quotes,
  }) {
    if (!configured) {
      if (_history.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('未配置 AI 服务，请到设置页填写'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _openSettings,
                child: const Text('去设置'),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          Expanded(child: _messageList(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                const Expanded(child: Text('未配置 AI 服务，请到设置页填写')),
                TextButton(
                  onPressed: _openSettings,
                  child: const Text('去设置'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _spoilerBar(context),
        Expanded(child: _messageList(context)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_readOnlyThread == null) _composer(quotes) else _jumpButton(),
      ],
    );
  }

  Widget _spoilerBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Icon(
            _spoilerEnabled ? Icons.visibility : Icons.visibility_off,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _spoilerEnabled ? '允许剧透：可以聊当前页之后的情节' : '不剧透：只聊当前页及之前',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Switch(
            key: const Key('companion-spoiler-toggle'),
            value: _spoilerEnabled,
            onChanged: (value) => setState(() => _spoilerEnabled = value),
          ),
        ],
      ),
    );
  }

  Widget _messageList(BuildContext context) {
    final readOnly = _readOnlyThread;
    final memoryHintHidden = ref.watch(companionMemoryHintHiddenProvider);
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: [
        if (readOnly != null)
          Container(
            key: const Key('companion-readonly-banner'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '保存在第 ${readOnly.chapterIndex + 1} 章，当前为只读',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else if (!memoryHintHidden)
          Container(
            key: const Key('companion-memory-chip'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.chapterIndex == 0
                        ? '暂无前序章节对话'
                        : '引用之前章节的对话纪要（≤400 字），不读取后面的章节',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  key: const Key('companion-memory-chip-close'),
                  tooltip: '关闭提示',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  onPressed: () => ref
                      .read(companionMemoryHintHiddenProvider.notifier)
                      .hide(),
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (_modeNotice != null) _ModeNotice(mode: _modeNotice!),
        for (var index = 0; index < _history.length; index++)
          _Bubble(
            text: _history[index].content,
            isUser: _history[index].role == ChatRole.user,
            speaking: _speakingIndex == index,
            onSpeak: _history[index].role == ChatRole.user
                ? null
                : () => unawaited(
                      _speak(_history[index].content, index),
                    ),
          ),
        if (_streaming.isNotEmpty) _Bubble(text: _streaming, isUser: false),
        if (_busy && _streaming.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _jumpButton() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('companion-go-to-chapter'),
          onPressed: () {
            final thread = _readOnlyThread;
            if (thread == null) return;
            _pendingThreadId = thread.id;
            _pendingChapterIndex = thread.chapterIndex;
            widget.onGoToChapter?.call(thread.chapterIndex);
          },
          child: const Text('前往该章'),
        ),
      ),
    );
  }

  Widget _composer(List<String> quotes) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quotes.isNotEmpty) _quoteChips(quotes),
          Row(
            children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _handleComposerKey,
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '问问这一章…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              IconButton(
                tooltip: '发送',
                icon: const Icon(Icons.send),
                onPressed: _busy ? null : _send,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quoteChips(List<String> quotes) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const Key('companion-quote-list'),
      children: [
        for (var index = 0; index < quotes.length; index++)
          Container(
            key: Key('companion-quote-$index'),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              border: Border(left: BorderSide(color: scheme.primary, width: 3)),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(8),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '引用',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        quotes[index],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('companion-quote-remove-$index'),
                  tooltip: '移除引用',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  onPressed: () => ref
                      .read(companionQuotesProvider.notifier)
                      .removeAt(index),
                  icon: Icon(
                    Icons.close,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> _openModeSheet() async {
    final before = ref.read(personaModeProvider);
    final picked = await showPersonaModeSheet(context);
    if (!mounted || picked == null || picked == before) return;
    setState(() => _modeNotice = picked);
    _scrollToEnd();
  }

  void _openMemorySheet() {
    final page = widget.currentPageText.trim();
    final text = page.isEmpty ? widget.chapterText : page;
    final label = [widget.bookTitle, widget.chapterTitle]
        .where((part) => part.trim().isNotEmpty)
        .join(' · ');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CompanionMemorySheet(
        initialText: text,
        contextLabel: label,
      ),
    );
  }
}

class _QuotedBlock extends StatelessWidget {
  const _QuotedBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('companion-quoted-block'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '引用',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.isUser,
    this.onSpeak,
    this.speaking = false,
  });

  final String text;
  final bool isUser;

  /// Set for assistant replies: reads this bubble aloud.
  final VoidCallback? onSpeak;

  /// Whether this bubble is the one being spoken right now.
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final speak = onSpeak;
    final ({String? quote, String body}) parsed = isUser
        ? parseCompanionMessage(text)
        : (quote: null, body: text);
    final quote = parsed.quote;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quote != null && quote.trim().isNotEmpty)
              _QuotedBlock(text: quote),
            if (parsed.body.isNotEmpty) Text(parsed.body),
            if (speak != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: speaking ? '正在朗读' : '朗读',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(
                    speaking ? Icons.graphic_eq : Icons.volume_up_outlined,
                  ),
                  onPressed: speak,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The current voice, as a chip the reader can tap to change it.
class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode, required this.onTap});

  final PersonaMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.6),
      shape: const StadiumBorder(),
      child: InkWell(
        key: const Key('companion-mode-pill'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(modeIcon(mode), size: 14),
              const SizedBox(width: 4),
              Text(mode.shortLabel, style: Theme.of(context).textTheme.labelMedium),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// One quiet line saying which voice took over.
class _ModeNotice extends StatelessWidget {
  const _ModeNotice({required this.mode});

  final PersonaMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(modeIcon(mode), size: 13, color: scheme.outline),
          const SizedBox(width: 4),
          Text(
            '已切到${mode.label}',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
