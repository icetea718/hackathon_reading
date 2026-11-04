import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.bookTitle,
    this.onPickBook,
    this.onClearBook,
  });

  final Future<void> Function(String text) onSend;
  final VoidCallback onStop;
  final bool streaming;
  final bool enabled;
  final bool webEnabled;
  final ValueChanged<bool> onWebChanged;

  /// False means the web provider has no key: tapping the chip explains how.
  final bool webConfigured;

  /// Title of the shelf book the answers should be grounded in.
  final String? bookTitle;
  final VoidCallback? onPickBook;
  final VoidCallback? onClearBook;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Fills the input from a suggestion chip without sending it.
  void fill(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _focus.requestFocus();
  }

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
    try {
      await widget.onSend(text);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送失败，请重试')),
      );
    }
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
            Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): _SendIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  _SendIntent: CallbackAction<_SendIntent>(
                    onInvoke: (_) {
                      _submit();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  key: const Key('chat-input'),
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: '问点什么…',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _WebChip(
                  active: widget.webEnabled,
                  onPressed: widget.enabled ? _toggleWeb : null,
                ),
                const SizedBox(width: 8),
                _BookControl(
                  title: widget.bookTitle,
                  enabled: widget.enabled,
                  onPick: widget.onPickBook,
                  onClear: widget.onClearBook,
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

/// Either "选择书" or the chip naming the book already attached.
class _BookControl extends StatelessWidget {
  const _BookControl({
    required this.title,
    required this.enabled,
    this.onPick,
    this.onClear,
  });

  final String? title;
  final bool enabled;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final picked = title;
    if (picked == null) {
      return Tooltip(
        message: '选一本书，让回答依据书里的内容',
        child: TextButton.icon(
          key: const Key('chat-book'),
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: const Text('选择书'),
        ),
      );
    }
    return InputChip(
      key: const Key('chat-book-chip'),
      avatar: const Icon(Icons.menu_book_outlined, size: 16),
      label: Text(
        picked,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: onClear,
      deleteButtonTooltipMessage: '取消引用这本书',
      visualDensity: VisualDensity.compact,
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

class _SendIntent extends Intent {
  const _SendIntent();
}
