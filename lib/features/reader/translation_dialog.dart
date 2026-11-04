import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../assistant/assistant_service.dart';
import '../../assistant/translation_exception.dart';
import '../../assistant/translation_segmenter.dart';

/// A small popup that streams a translation into view.
///
/// The dialog owns nothing but presentation: it subscribes to
/// [AssistantService.translate] and appends every chunk it receives.
class TranslationDialog extends StatefulWidget {
  const TranslationDialog({
    super.key,
    required this.title,
    required this.sourceText,
    required this.service,
    this.targetLang = 'zh-CN',
    this.targetLabel = '简体中文',
  });

  final String title;
  final String sourceText;
  final AssistantService service;
  final String targetLang;
  final String targetLabel;

  @override
  State<TranslationDialog> createState() => _TranslationDialogState();
}

class _TranslationDialogState extends State<TranslationDialog> {
  final ScrollController _scrollController = ScrollController();
  final StringBuffer _buffer = StringBuffer();
  StreamSubscription<String>? _subscription;
  String? _error;
  bool _finished = false;
  bool _alreadyChinese = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _start() {
    _subscription?.cancel();
    _buffer.clear();
    _error = null;
    _finished = false;
    _alreadyChinese = false;

    if (isPredominantlyChinese(widget.sourceText)) {
      _alreadyChinese = true;
      _finished = true;
      return;
    }

    _subscription = widget.service
        .translate(widget.sourceText, targetLang: widget.targetLang)
        .listen(
      _appendChunk,
      onError: _onError,
      onDone: () {
        if (!mounted) return;
        setState(() => _finished = true);
      },
      cancelOnError: true,
    );
  }

  void _appendChunk(String chunk) {
    if (!mounted || chunk.isEmpty) return;
    setState(() {
      if (_buffer.isNotEmpty) _buffer.write('\n');
      _buffer.write(chunk);
    });
    _scrollToBottom();
  }

  void _onError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error is TranslationException ? error.message : _describe(error);
      _finished = true;
    });
  }

  String _describe(Object error) {
    if (error is AssistantNotConfiguredException) return '未配置 AI 服务';
    return error.toString();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _copy() async {
    final text = _buffer.toString();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('译文已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final translated = _buffer.toString();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.translate, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '目标语言：${widget.targetLabel}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: _buildBody(theme, translated),
              ),
            ),
            if (!_finished && _error == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: translated.isEmpty ? null : _copy,
          child: const Text('复制译文'),
        ),
        if (_error != null)
          TextButton(
            onPressed: () => setState(_start),
            child: const Text('重试'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, String translated) {
    final error = _error;
    if (error != null) {
      return Text(
        error,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    if (_alreadyChinese) {
      return Text('原文已是中文，无需翻译。', style: theme.textTheme.bodyMedium);
    }
    if (translated.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SelectableText(
      translated,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
    );
  }
}
