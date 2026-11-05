import 'package:flutter/material.dart';

import '../../assistant/reading_context.dart';

/// A compact bubble chat that sits beside the companion.
///
/// It owns no conversation state: the reader page keeps the per-chapter
/// history and streams answers in, so closing the panel loses nothing.
class CompanionChatPanel extends StatefulWidget {
  const CompanionChatPanel({
    super.key,
    required this.title,
    required this.messages,
    required this.streaming,
    required this.busy,
    required this.onSend,
    required this.onClose,
    this.onChangeSkin,
  });

  /// Chapter the thread belongs to, e.g. `陪读 · 第一部分`.
  final String title;
  final List<ChatMessage> messages;

  /// Answer tokens that arrived while the model is still talking.
  final String streaming;

  /// True while a request is in flight; the send button is disabled.
  final bool busy;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;

  /// Opens the skin picker; hidden when the host cannot swap characters.
  final VoidCallback? onChangeSkin;

  @override
  State<CompanionChatPanel> createState() => _CompanionChatPanelState();
}

class _CompanionChatPanelState extends State<CompanionChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(CompanionChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.streaming != widget.streaming) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _submit() {
    if (widget.busy) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    widget.onSend(text);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;

    return Material(
      key: const Key('companion-chat-panel'),
      color: scheme.surfaceContainerLow,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.onChangeSkin != null)
                  IconButton(
                    key: const Key('companion-skin-open'),
                    icon: const Icon(Icons.pets, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: '换形象',
                    onPressed: widget.onChangeSkin,
                  ),
                IconButton(
                  key: const Key('companion-chat-close'),
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: '收起',
                  onPressed: widget.onClose,
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minHeight: 48),
              child: SingleChildScrollView(
                key: const Key('companion-chat-messages'),
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final message in widget.messages)
                      _Bubble(
                        content: message.content,
                        fromReader: message.role == ChatRole.user,
                        style: style,
                      ),
                    if (widget.streaming.isNotEmpty)
                      _Bubble(
                        content: widget.streaming,
                        fromReader: false,
                        style: style,
                        pending: true,
                      )
                    else if (widget.busy)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          '……',
                          style: style?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('companion-chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '和它说点什么',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('companion-chat-send'),
                  tooltip: '发送',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: widget.busy ? null : _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.content,
    required this.fromReader,
    required this.style,
    this.pending = false,
  });

  final String content;
  final bool fromReader;
  final TextStyle? style;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: fromReader ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: fromReader
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          pending ? '$content…' : content,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(
            color: fromReader
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
