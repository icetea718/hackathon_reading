import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../illustration/illustration_config.dart';
import '../../illustration/illustration_models.dart';
import 'illustration_jobs.dart';
import '../memory_book/memory_book_dialogs.dart';
import '../memory_book/memory_book_providers.dart';
import '../settings/settings_page.dart';

class IllustrationComposerPage extends ConsumerStatefulWidget {
  const IllustrationComposerPage({
    super.key,
    this.initialText = '',
    this.contextLabel = '',
    this.preselectBookId,
    this.jobId,
  });

  final String initialText;
  final String contextLabel;
  final String? preselectBookId;

  /// Opens an existing background job instead of starting a fresh one.
  final String? jobId;

  @override
  ConsumerState<IllustrationComposerPage> createState() =>
      _IllustrationComposerPageState();
}

class _IllustrationComposerPageState
    extends ConsumerState<IllustrationComposerPage> {
  late final TextEditingController _text;
  String? _jobId;
  bool _saving = false;

  static const _maxInputChars = 6000;

  @override
  void initState() {
    super.initState();
    _jobId = widget.jobId;
    final job = widget.jobId == null
        ? null
        : ref.read(illustrationJobProvider);
    final initial = widget.initialText.trim().isNotEmpty
        ? widget.initialText.trim()
        : (job?.text.trim() ?? '');
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
    final job = ref.watch(illustrationJobProvider);
    final myJob = job != null && job.id == _jobId ? job : null;
    final running = myJob?.isRunning ?? false;
    final result = myJob?.result;
    final error = myJob?.error;

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
              if (running) ...[
                const SizedBox(height: 18),
                _progressCard(myJob?.stage),
              ],
              if (error != null) ...[
                const SizedBox(height: 18),
                _errorCard(error),
              ],
              if (result != null) ...[
                const SizedBox(height: 18),
                _previewCard(result),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: running || result != null ? null : _generate,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('开始生成'),
                  ),
                  const SizedBox(width: 12),
                  if (result != null || error != null)
                    OutlinedButton(
                      onPressed: running ? null : _reset,
                      child: const Text('重新生成'),
                    ),
                  const Spacer(),
                  if (result != null)
                    TextButton(
                      onPressed: running ? null : _discard,
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
                '插画需要一个支持生图的接口和图像模型。到设置里填写一次即可，'
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
            '当前插画接口是 DeepSeek，它没有生图接口。请到设置里换一个支持生图的接口。',
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

  Widget _progressCard(IllustrationStage? stage) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stage?.label ?? '准备中…',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              '生成一张需要几十秒，可以先去读，画完会通知你。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('illustration-stop'),
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('停止生成'),
                ),
                OutlinedButton.icon(
                  key: const Key('illustration-background'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('后台生成，先去读'),
                ),
              ],
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
                onPressed: _saving ? null : _save,
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

  void _generate() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _snack('请先粘贴一段小说文段。');
      return;
    }
    final id = ref
        .read(illustrationJobProvider.notifier)
        .start(text: text, label: widget.contextLabel);
    if (id == null) {
      _snack('已有插画在生成中，等它画完再试。');
      return;
    }
    setState(() => _jobId = id);
  }

  Future<void> _save() async {
    final job = ref.read(illustrationJobProvider);
    final result = job?.result;
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
        excerpt: job?.text ?? _text.text,
        medium: result.plan.medium,
      );
      if (!mounted) return;
      ref.read(illustrationJobProvider.notifier).dismiss();
      _snack('已保存到回忆录。');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('保存失败：$error');
    }
  }

  void _stop() {
    ref.read(illustrationJobProvider.notifier).cancel();
    setState(() => _jobId = null);
    _snack('已停止生成。');
  }

  void _reset() {
    ref.read(illustrationJobProvider.notifier).dismiss();
    setState(() => _jobId = null);
  }

  void _discard() {
    ref.read(illustrationJobProvider.notifier).dismiss();
    Navigator.of(context).pop();
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
