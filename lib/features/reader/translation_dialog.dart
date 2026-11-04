import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../assistant/assistant_service.dart';
import '../../assistant/translation_exception.dart';
import '../../assistant/translation_segmenter.dart';
import '../../data/repositories/translation_cache_repository.dart';

/// A small popup that streams a translation into view.
///
/// The dialog owns nothing but presentation: it looks the text up in
/// [TranslationCacheStore] first and only subscribes to
/// [AssistantService.translate] when nothing is cached, so a remembered
/// passage opens instantly. Writing results back is the job of
/// [CachedTranslationService], which also covers whole-chapter translation.
class TranslationDialog extends StatefulWidget {
  const TranslationDialog({
    super.key,
    required this.title,
    required this.sourceText,
    required this.service,
    required this.cache,
    this.targetLang = 'zh-CN',
    this.targetLabel = '简体中文',
  });

  final String title;
  final String sourceText;
  final AssistantService service;
  final TranslationCacheStore cache;
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
  bool _alreadyChinese = false;
  bool _fromCache = false;
  bool _translating = false;

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

  Future<void> _start({bool ignoreCache = false}) async {
    await _subscription?.cancel();
    if (!mounted) return;
    _subscription = null;
    _buffer.clear();
    _error = null;
    _alreadyChinese = false;
    _fromCache = false;
    _translating = true;

    if (isPredominantlyChinese(widget.sourceText)) {
      setState(() {
        _alreadyChinese = true;
        _translating = false;
      });
      return;
    }

    if (!ignoreCache) {
      final cached = await _readCache();
      if (!mounted) return;
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _buffer.write(cached);
          _fromCache = true;
          _translating = false;
        });
        return;
      }
    }

    setState(() {});
    _subscription = widget.service
        .translate(widget.sourceText, targetLang: widget.targetLang)
        .listen(
          _appendChunk,
          onError: _onError,
          onDone: _onDone,
          cancelOnError: true,
        );
  }

  Future<String?> _readCache() async {
    try {
      return await widget.cache.find(
        widget.sourceText,
        targetLang: widget.targetLang,
      );
    } catch (_) {
      // A broken cache must never block translation.
      return null;
    }
  }

  void _appendChunk(String chunk) {
    if (!mounted || chunk.isEmpty) return;
    setState(() => _buffer.write(chunk));
    _scrollToBottom();
  }

  void _onError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error is TranslationException ? error.message : _describe(error);
      _translating = false;
    });
  }

  void _onDone() {
    if (!mounted) return;
    setState(() => _translating = false);
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

  /// Drops the remembered translation and asks the model again.
  Future<void> _retranslate() async {
    try {
      await widget.cache.remove(
        widget.sourceText,
        targetLang: widget.targetLang,
      );
    } catch (_) {
      // Losing the delete is fine: we still try a fresh request.
    }
    await _start(ignoreCache: true);
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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.translate, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _statusLine(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 80, maxHeight: 320),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: _buildBody(theme, translated),
                ),
              ),
              if (_translating)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: translated.isEmpty ? null : _copy,
                    child: const Text('复制译文'),
                  ),
                  if (_fromCache)
                    TextButton(
                      onPressed: _retranslate,
                      child: const Text('重新翻译'),
                    ),
                  if (_error != null)
                    TextButton(
                      onPressed: _retranslate,
                      child: const Text('重试'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLine() {
    final base = '目标语言：${widget.targetLabel}';
    if (_fromCache) return '$base · 来自本地缓存';
    if (_translating) return '$base · 翻译中…';
    return base;
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: _translating
              ? const CircularProgressIndicator()
              : const Text('没有译文'),
        ),
      );
    }
    return SelectableText(
      translated,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
    );
  }
}
