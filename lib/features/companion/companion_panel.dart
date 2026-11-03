import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../assistant/assistant_service.dart';
import '../../assistant/reading_context.dart';
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

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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
      setState(() {
        if (buffer.isNotEmpty) {
          _history.add(
            ChatMessage(role: ChatRole.assistant, content: buffer.toString()),
          );
        }
        _streaming = '';
      });
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
                    for (final message in _history)
                      _Bubble(
                        text: message.content,
                        isUser: message.role == ChatRole.user,
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
  const _Bubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        child: Text(text),
      ),
    );
  }
}
