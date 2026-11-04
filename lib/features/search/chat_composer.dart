import 'package:flutter/material.dart';

/// Rounded input row: web toggle on the left, send (or stop) on the right.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.streaming,
    required this.enabled,
    required this.webEnabled,
    required this.onWebChanged,
    this.webConfigured = true,
  });

  final Future<void> Function(String text) onSend;
  final VoidCallback onStop;
  final bool streaming;
  final bool enabled;
  final bool webEnabled;
  final ValueChanged<bool> onWebChanged;

  /// False means the web provider has no key: tapping the chip explains how.
  final bool webConfigured;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.streaming || !widget.enabled) return;
    _controller.clear();
    await widget.onSend(text);
  }

  void _toggleWeb() {
    if (!widget.webConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先在设置里填 Tavily API Key')),
      );
      return;
    }
    widget.onWebChanged(!widget.webEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('chat-input'),
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: '问点什么…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
            Row(
              children: [
                _WebChip(
                  active: widget.webEnabled,
                  onPressed: widget.enabled ? _toggleWeb : null,
                ),
                const Spacer(),
                if (widget.streaming)
                  IconButton(
                    key: const Key('chat-stop'),
                    tooltip: '停止',
                    onPressed: widget.onStop,
                    icon: const Icon(Icons.stop_circle_outlined),
                  )
                else
                  IconButton.filled(
                    key: const Key('chat-send'),
                    tooltip: '发送',
                    onPressed: widget.enabled ? _submit : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WebChip extends StatelessWidget {
  const _WebChip({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? '联网搜索已开启' : '联网搜索已关闭',
      child: FilterChip(
        key: const Key('chat-web-toggle'),
        avatar: Icon(
          active ? Icons.language : Icons.language_outlined,
          size: 16,
        ),
        label: const Text('联网'),
        selected: active,
        onSelected: onPressed == null ? null : (_) => onPressed!(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
