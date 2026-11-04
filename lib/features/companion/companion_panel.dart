import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../assistant/assistant_service.dart';
import '../../assistant/reading_context.dart';
import '../../tts/tts_config.dart';
import '../../tts/tts_service.dart';
import '../settings/settings_page.dart';

/// Bottom-sheet companion chat for the chapter the reader is looking at.
class CompanionPanel extends ConsumerStatefulWidget {
  const CompanionPanel({
    super.key,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.chapterText,
    required this.chapterCharOffset,
    this.bookTitle = '',
    this.author = '',
  });

  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final String chapterText;
  final int? chapterCharOffset;
  final String bookTitle;
  final String author;

  @override
  ConsumerState<CompanionPanel> createState() => _CompanionPanelState();
}

class _CompanionPanelState extends ConsumerState<CompanionPanel> {
  final List<ChatMessage> _history = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _streaming = '';
  bool _busy = false;
  String? _error;

  late final TtsService _tts;
  StreamSubscription<TtsStatus>? _ttsSubscription;
  TtsStatus _ttsStatus = const TtsStatus();

  /// History entry currently being spoken; null when nothing is playing.
  int? _speakingIndex;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    _ttsSubscription = _tts.statuses.listen(_onTtsStatus);
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

  Future<void> _speak(String text, int? index, {bool force = false}) async {
    setState(() => _speakingIndex = index);
    await _tts.speak(text, force: force);
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
      );

  Future<void> _stream(
    Stream<String> Function(AssistantService service) start,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _streaming = '';
    });
    try {
      final service = await ref.read(assistantServiceProvider.future);
      if (!service.isConfigured) {
        setState(() => _error = '未配置 AI 服务，请到设置页填写');
        return;
      }
      final buffer = StringBuffer();
      await for (final chunk in start(service)) {
        buffer.write(chunk);
        if (!mounted) return;
        setState(() => _streaming = buffer.toString());
        _scrollToEnd();
      }
      if (!mounted) return;
      final reply = buffer.toString();
      setState(() {
        if (reply.isNotEmpty) {
          _history.add(
            ChatMessage(role: ChatRole.assistant, content: reply),
          );
        }
        _streaming = '';
      });
      if (reply.isNotEmpty && _autoSpeak) {
        unawaited(_speak(reply, _history.length - 1));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '出错了：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() => _history.add(ChatMessage(role: ChatRole.user, content: text)));
    await _stream((service) => service.chat(_context, List.of(_history), text));
  }

  Future<void> _summarize() => _stream((service) => service.summarizeChapter(_context));

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

  bool get _autoSpeak {
    final config = ref.read(ttsConfigProvider);
    return config is AsyncData<TtsConfig> && config.value.autoSpeak;
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
    final service = ref.watch(assistantServiceProvider);
    final configured = service is AsyncData<AssistantService> &&
        service.value.isConfigured;
    final loading = service is AsyncLoading<AssistantService>;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
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
                  TextButton(
                    onPressed: configured && !_busy ? _summarize : null,
                    child: const Text('总结本章'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (!configured)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('未配置 AI 服务，请到设置页填写'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsPage(),
                          ),
                        ),
                        child: const Text('去设置'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (var index = 0; index < _history.length; index++)
                      _Bubble(
                        text: _history[index].content,
                        isUser: _history[index].role == ChatRole.user,
                        speaking: _speakingIndex == index,
                        onSpeak: _history[index].role == ChatRole.user
                            ? null
                            : () => unawaited(
                                  _speak(_history[index].content, index,
                                      force: true),
                                ),
                      ),
                    if (_streaming.isNotEmpty)
                      _Bubble(text: _streaming, isUser: false),
                    if (_busy && _streaming.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
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
              ),
            ],
          ],
        ),
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
            Text(text),
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
