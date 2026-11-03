import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../distill/llm/llm_client.dart';
import '../../distill/llm/llm_config.dart';
import '../../tts/tts_config.dart';

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

  final _ttsBaseUrl = TextEditingController();
  final _ttsVoice = TextEditingController();
  final _ttsSpeed = TextEditingController();
  final _ttsVolume = TextEditingController();
  bool _ttsEnabled = TtsConfig.defaults.enabled;
  bool _ttsAutoSpeak = TtsConfig.defaults.autoSpeak;

  bool _loaded = false;
  bool _testing = false;
  bool _testingVoice = false;

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
    _ttsBaseUrl.dispose();
    _ttsVoice.dispose();
    _ttsSpeed.dispose();
    _ttsVolume.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ref.read(llmConfigStoreProvider).load();
    final voice = await ref.read(ttsConfigStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _baseUrl.text = config.baseUrl;
      _model.text = config.model;
      _apiKey.text = config.apiKey;
      _temperature.text = '${config.temperature}';
      _maxChunkChars.text = '${config.maxChunkChars}';
      _ttsBaseUrl.text = voice.baseUrl;
      _ttsVoice.text = voice.voice;
      _ttsSpeed.text = '${voice.speed}';
      _ttsVolume.text = '${voice.volume}';
      _ttsEnabled = voice.enabled;
      _ttsAutoSpeak = voice.autoSpeak;
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
    await ref.read(ttsConfigStoreProvider).save(_voiceFromForm());
    ref.invalidate(ttsConfigProvider);
    if (!mounted || !announce) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  TtsConfig _voiceFromForm() {
    final speed = double.tryParse(_ttsSpeed.text.trim());
    final volume = double.tryParse(_ttsVolume.text.trim());
    final voice = _ttsVoice.text.trim();
    return TtsConfig(
      baseUrl: _ttsBaseUrl.text.trim(),
      voice: voice.isEmpty ? TtsConfig.defaults.voice : voice,
      speed: (speed ?? TtsConfig.defaults.speed).clamp(0.6, 1.6).toDouble(),
      volume: (volume ?? TtsConfig.defaults.volume).clamp(0, 1).toDouble(),
      enabled: _ttsEnabled,
      autoSpeak: _ttsAutoSpeak,
    );
  }

  Future<void> _testVoice() async {
    if (_testingVoice) return;
    setState(() => _testingVoice = true);
    final config = _voiceFromForm();
    await _save(announce: false);
    // Use the values on screen: the shared client still holds the previous
    // snapshot until the settings provider has reloaded from the database.
    final client = ref.read(ttsClientFactoryProvider)(config);
    bool reachable;
    try {
      reachable = await client.ping();
    } finally {
      client.dispose();
    }
    if (!mounted) return;
    setState(() => _testingVoice = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reachable
              ? '语音服务可用（${config.baseUrl}）'
              : '语音服务不可用：连不上 ${config.baseUrl}/health',
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    // Save first so the shared client picks up the values just typed.
    final config = _configFromForm();
    await _save(announce: false);
    String message;
    final client = ref.read(llmClientFactoryProvider)(config);
    try {
      await client.completeJson(const [LlmMessage(LlmRole.user, 'ping')]);
      message = '连接成功';
    } catch (error) {
      message = '连接失败：$error';
    } finally {
      client.dispose();
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
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '朗读（GPT-SoVITS）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile(
                  key: const Key('tts-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用朗读'),
                  subtitle: const Text('陪读回复右侧会出现喇叭按钮'),
                  value: _ttsEnabled,
                  onChanged: (value) => setState(() => _ttsEnabled = value),
                ),
                TextField(
                  key: const Key('tts-base-url'),
                  controller: _ttsBaseUrl,
                  decoration: const InputDecoration(
                    labelText: '语音服务地址',
                    hintText: 'http://127.0.0.1:9880',
                    helperText: '本机 GPT-SoVITS api_v2 的地址',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('tts-voice'),
                  controller: _ttsVoice,
                  decoration: const InputDecoration(
                    labelText: '音色',
                    helperText: 'xll / dfy / female / male，或自定义音色名',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('tts-speed'),
                        controller: _ttsSpeed,
                        decoration: const InputDecoration(
                          labelText: '语速（0.6–1.6）',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('tts-volume'),
                        controller: _ttsVolume,
                        decoration: const InputDecoration(
                          labelText: '音量（0–1）',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const Key('tts-auto-speak'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动朗读回复'),
                  subtitle: const Text('回复生成完就念，不用点喇叭'),
                  value: _ttsAutoSpeak,
                  onChanged: (value) => setState(() => _ttsAutoSpeak = value),
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
                    const SizedBox(width: 12),
                    OutlinedButton(
                      key: const Key('tts-test'),
                      onPressed: _testingVoice ? null : _testVoice,
                      child: _testingVoice
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('测试语音'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
