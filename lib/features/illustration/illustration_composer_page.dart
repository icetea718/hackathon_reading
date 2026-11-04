import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../illustration/illustration_config.dart';
import '../../illustration/illustration_models.dart';
import '../../illustration/illustration_service.dart';
import '../memory_book/memory_book_dialogs.dart';
import '../memory_book/memory_book_providers.dart';
import '../settings/settings_page.dart';

class IllustrationComposerPage extends ConsumerStatefulWidget {
  const IllustrationComposerPage({
    super.key,
    this.initialText = '',
    this.contextLabel = '',
    this.preselectBookId,
  });

  final String initialText;
  final String contextLabel;
  final String? preselectBookId;

  @override
  ConsumerState<IllustrationComposerPage> createState() =>
      _IllustrationComposerPageState();
}

class _IllustrationComposerPageState
    extends ConsumerState<IllustrationComposerPage> {
  late final TextEditingController _text;
  IllustrationStage? _stage;
  IllustrationResult? _result;
  String? _error;
  bool _busy = false;
  bool _saving = false;

  static const _maxInputChars = 6000;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialText.trim();
    _text = TextEditingController(
      text: initial.length <= _maxInputChars
          ? initial
          : initial.substring(0, _maxInputChars),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final illAsync = ref.watch(illustrationConfigProvider);
    final llmAsync = ref.watch(llmConfigProvider);
    final config = illAsync.value;
    final llm = llmAsync.value;
    final effective = config == null || llm == null ? null : config.resolve(llm);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生成插画'),
        actions: [
          IconButton(
            tooltip: '插画设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
            children: [
              if (widget.contextLabel.isNotEmpty) ...[
                Text(
                  widget.contextLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _text,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: '小说文段',
                  hintText: '粘贴一段有画面感的小说段落…',
                  helperText: '只会取前 6000 字；画面越具体，生成越稳。',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _configCard(effective, illAsync.isLoading || llmAsync.isLoading),
              if (_busy) ...[
                const SizedBox(height: 18),
                _progressCard(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                _errorCard(_error!),
              ],
              if (_result != null) ...[
                const SizedBox(height: 18),
                _previewCard(_result!),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy || _result != null ? null : _generate,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('开始生成'),
                  ),
                  const SizedBox(width: 12),
                  if (_result != null)
                    OutlinedButton(
                      onPressed: _busy ? null : _reset,
                      child: const Text('重新生成'),
                    ),
                  const Spacer(),
                  if (_result != null)
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('放弃'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _configCard(IllustrationEffective? effective, bool loading) {
    final theme = Theme.of(context);
    if (loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('正在读取插画配置…'),
            ],
          ),
        ),
      );
    }
    if (effective == null || !effective.isConfigured) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '还没有配置插画服务',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '插画需要火山方舟 Ark 的接口和图像模型。到设置里填写一次即可，'
                '可以复用上面的 API Key。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _openSettings,
                  child: const Text('去设置'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (effective.isDeepSeek) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '当前插画接口是 DeepSeek，它没有绘图接口。请到设置里把插画接口改成火山方舟 Ark。',
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
        ),
      );
    }
    final host = Uri.tryParse(effective.baseUrl)?.host ?? effective.baseUrl;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.brush_outlined),
        title: Text('插画服务：$host'),
        subtitle: Text(
          '聊天 ${effective.chatModel} · 图像 ${effective.imageModel}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton(
          onPressed: _openSettings,
          child: const Text('修改'),
        ),
      ),
    );
  }

  Widget _progressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _stage?.label ?? '准备中…',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              '生成一张需要几十秒，请不要关闭窗口。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(IllustrationResult result) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('成品预览', style: theme.textTheme.titleSmall),
                const SizedBox(width: 10),
                if (result.plan.medium.isNotEmpty)
                  Chip(
                    label: Text(result.plan.medium),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Image.file(
                result.finalFile,
                height: 430,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox(
                  height: 120,
                  child: Center(child: Text('图片读取失败')),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    result.sketchFile,
                    width: 84,
                    height: 112,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(width: 84, height: 112),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '草图会作为上色的参考图；回忆录里只保存成品图。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.book_outlined, size: 18),
                label: const Text('保存到回忆录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _snack('请先粘贴一段小说文段。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _stage = IllustrationStage.planning;
    });

    IllustrationService? service;
    try {
      final config = await ref.read(illustrationConfigProvider.future);
      final llm = await ref.read(llmConfigProvider.future);
      final effective = config.resolve(llm);
      if (!effective.isConfigured) {
        throw IllustrationException(
          '还没有配置插画服务。请到设置里填写 Ark 接口、API Key 和图像模型。',
        );
      }
      service = IllustrationService(effective: effective);
      final result = await service.generate(
        text,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
        _stage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
        _stage = null;
      });
    } finally {
      service?.dispose();
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving) return;
    final bookId = await pickMemoryBookDialog(
      context,
      ref,
      selectedId: widget.preselectBookId,
    );
    if (bookId == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final store = await ref.read(memoryBookStoreProvider.future);
      await store.addPage(
        bookId: bookId,
        sourcePath: result.finalFile.path,
        excerpt: _text.text,
        medium: result.plan.medium,
      );
      if (!mounted) return;
      _snack('已保存到回忆录。');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('保存失败：$error');
    }
  }

  void _reset() {
    setState(() {
      _result = null;
      _error = null;
      _stage = null;
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
