import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../distill/llm/llm_client.dart';
import '../../distill/llm/llm_config.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _temperature = TextEditingController();
  final _maxChunkChars = TextEditingController();

  bool _loaded = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _temperature.dispose();
    _maxChunkChars.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ref.read(llmConfigStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _baseUrl.text = config.baseUrl;
      _model.text = config.model;
      _apiKey.text = config.apiKey;
      _temperature.text = '${config.temperature}';
      _maxChunkChars.text = '${config.maxChunkChars}';
      _loaded = true;
    });
  }

  LlmConfig _configFromForm() {
    return LlmConfig(
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      apiKey: _apiKey.text.trim(),
      temperature: double.tryParse(_temperature.text.trim()) ??
          LlmConfig.defaultTemperature,
      maxChunkChars: int.tryParse(_maxChunkChars.text.trim()) ??
          LlmConfig.defaultMaxChunkChars,
    );
  }

  Future<void> _save({bool announce = true}) async {
    await ref.read(llmConfigStoreProvider).save(_configFromForm());
    ref.invalidate(llmConfigProvider);
    if (!mounted || !announce) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    // Save first so the shared client picks up the values just typed.
    await _save(announce: false);
    String message;
    try {
      await ref
          .read(llmClientProvider)
          .completeJson(const [LlmMessage(LlmRole.user, 'ping')]);
      message = '连接成功';
    } catch (error) {
      message = '连接失败：$error';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: const Key('llm-base-url'),
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: '接口地址',
                    hintText: 'https://api.deepseek.com/v1',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('llm-model'),
                  controller: _model,
                  decoration: const InputDecoration(labelText: '模型'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('llm-api-key'),
                  controller: _apiKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    helperText: '保存在本机数据库中，明文存储',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('llm-temperature'),
                  controller: _temperature,
                  decoration: const InputDecoration(
                    labelText: '温度（0–2）',
                    helperText: '越小越稳定，推荐 0.3',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('llm-max-chunk-chars'),
                  controller: _maxChunkChars,
                  decoration: const InputDecoration(
                    labelText: '单块字数上限',
                    helperText: '2000–20000，默认 6000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => _save(),
                      child: const Text('保存'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _testing ? null : _testConnection,
                      child: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('测试连接'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
