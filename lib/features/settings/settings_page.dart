import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../distill/llm/llm_client.dart';
import '../../distill/llm/llm_config.dart';
import '../../illustration/illustration_config.dart';
import '../../search/search_config.dart';
import '../../tts/tts_client.dart';
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

  final _illBaseUrl = TextEditingController();
  final _illApiKey = TextEditingController();
  final _illChatModel = TextEditingController();
  final _illImageModel = TextEditingController();

  final _ttsBaseUrl = TextEditingController();
  final _ttsVoice = TextEditingController();
  final _ttsSpeed = TextEditingController();
  final _ttsVolume = TextEditingController();
  bool _ttsEnabled = TtsConfig.defaults.enabled;
  bool _ttsAutoSpeak = TtsConfig.defaults.autoSpeak;

  final _searchKey = TextEditingController();
  String _searchProvider = SearchConfig.off;

  bool _loaded = false;
  bool _testing = false;
  bool _testingIllustration = false;
  bool _testingVoice = false;
  bool _testingSearch = false;

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
    _illBaseUrl.dispose();
    _illApiKey.dispose();
    _illChatModel.dispose();
    _illImageModel.dispose();
    _ttsBaseUrl.dispose();
    _ttsVoice.dispose();
    _ttsSpeed.dispose();
    _ttsVolume.dispose();
    _searchKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ref.read(llmConfigStoreProvider).load();
    final illustration =
        await ref.read(illustrationConfigStoreProvider).load();
    final voice = await ref.read(ttsConfigStoreProvider).load();
    final search = await ref.read(searchConfigStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _baseUrl.text = config.baseUrl;
      _model.text = config.model;
      _apiKey.text = config.apiKey;
      _temperature.text = '${config.temperature}';
      _maxChunkChars.text = '${config.maxChunkChars}';
      _illBaseUrl.text = illustration.baseUrl;
      _illApiKey.text = illustration.apiKey;
      _illChatModel.text = illustration.chatModel;
      _illImageModel.text = illustration.imageModel;
      _ttsBaseUrl.text = voice.baseUrl;
      _ttsVoice.text = voice.voice;
      _ttsSpeed.text = '${voice.speed}';
      _ttsVolume.text = '${voice.volume}';
      _ttsEnabled = voice.enabled;
      _ttsAutoSpeak = voice.autoSpeak;
      _searchProvider = search.provider;
      _searchKey.text = search.apiKey;
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
    await ref
        .read(illustrationConfigStoreProvider)
        .save(_illustrationFromForm());
    ref.invalidate(illustrationConfigProvider);
    await ref.read(ttsConfigStoreProvider).save(_voiceFromForm());
    ref.invalidate(ttsConfigProvider);
    await ref.read(searchConfigStoreProvider).save(_searchFromForm());
    ref.invalidate(searchConfigProvider);
    if (!mounted || !announce) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  SearchConfig _searchFromForm() {
    return SearchConfig(
      provider: _searchProvider,
      apiKey: _searchKey.text.trim(),
    );
  }

  IllustrationConfig _illustrationFromForm() {
    return IllustrationConfig(
      baseUrl: _illBaseUrl.text.trim(),
      apiKey: _illApiKey.text.trim(),
      chatModel: _illChatModel.text.trim().isEmpty
          ? IllustrationConfig.defaultChatModel
          : _illChatModel.text.trim(),
      imageModel: _illImageModel.text.trim().isEmpty
          ? IllustrationConfig.defaultImageModel
          : _illImageModel.text.trim(),
    );
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
    TtsProbe probe;
    try {
      probe = await client.probe();
    } finally {
      client.dispose();
    }
    if (!mounted) return;
    setState(() => _testingVoice = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(probe.ok ? probe.message : '语音服务不可用：${probe.message}'),
        duration: const Duration(seconds: 6),
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

  Future<void> _testSearch() async {
    if (_testingSearch) return;
    setState(() => _testingSearch = true);
    final config = _searchFromForm();
    await _save(announce: false);
    final provider = ref.read(searchProviderFactoryProvider)(config);
    String message;
    try {
      final hits = await provider.search('ping', count: 1);
      message = '搜索成功：${hits.length} 条';
    } catch (error) {
      message = '搜索失败：$error';
    }
    if (!mounted) return;
    setState(() => _testingSearch = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testIllustration() async {
    if (_testingIllustration) return;
    setState(() => _testingIllustration = true);
    final effective = _illustrationFromForm().resolve(_configFromForm());
    String message;
    if (!effective.isConfigured) {
      message = '请先填写插画 API Key（或沿用上面的 API Key）';
    } else if (effective.isDeepSeek) {
      message = 'DeepSeek 不支持生图，请把插画接口改成一个支持生图的接口地址';
    } else {
      final client = ref.read(llmClientFactoryProvider)(
        LlmConfig(
          baseUrl: effective.baseUrl,
          model: effective.chatModel,
          apiKey: effective.apiKey,
          temperature: 0.4,
        ),
      );
      try {
        await client.completeJson(const [LlmMessage(LlmRole.user, 'ping')]);
        message = '插画聊天接口可用（生图接口未单独测试）';
      } catch (error) {
        message = '插画配置连接失败：$error';
      } finally {
        client.dispose();
      }
    }
    if (!mounted) return;
    setState(() => _testingIllustration = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
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
                  '联网搜索（搜模式）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('search-provider'),
                  initialValue: _searchProvider,
                  decoration: const InputDecoration(labelText: '搜索服务'),
                  items: const [
                    DropdownMenuItem(
                      value: SearchConfig.off,
                      child: Text('关闭（不联网）'),
                    ),
                    DropdownMenuItem(
                      value: SearchConfig.free,
                      child: Text('免费搜索（免 Key）'),
                    ),
                    DropdownMenuItem(
                      value: SearchConfig.tavily,
                      child: Text('Tavily'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _searchProvider = value ?? SearchConfig.off,
                  ),
                ),
                if (_searchProvider == SearchConfig.tavily) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('search-api-key'),
                    controller: _searchKey,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Tavily API Key',
                      helperText: '没填就只靠模型自己回答，不联网检索',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('search-test'),
                    onPressed: _testingSearch ? null : _testSearch,
                    child: _testingSearch
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('测试搜索'),
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '插画（生图）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '生图可以使用任意支持图片生成的 OpenAI 兼容接口；接口/Key 留空时沿用上面的 AI 服务。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('illustration-base-url'),
                  controller: _illBaseUrl,
                  decoration: const InputDecoration(
                    labelText: '插画接口地址（可选）',
                    hintText: 'https://api.openai.com/v1',
                    helperText: '留空则沿用上面的接口地址；填到 /v1 或 /api/v3 即可',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('illustration-api-key'),
                  controller: _illApiKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '插画 API Key（可选）',
                    helperText: '留空则复用上面的 API Key',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('illustration-chat-model'),
                  controller: _illChatModel,
                  decoration: const InputDecoration(
                    labelText: '插画聊天模型',
                    helperText: '默认 doubao-seed-2-1-pro-260915',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('illustration-image-model'),
                  controller: _illImageModel,
                  decoration: const InputDecoration(
                    labelText: '图像模型',
                    helperText: '例如 gpt-image-1、doubao-seedream-5-0-pro-260628',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('illustration-test'),
                    onPressed: _testingIllustration ? null : _testIllustration,
                    child: _testingIllustration
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('测试插画配置'),
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '朗读（GPT-SoVITS / chino-tts）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile(
                  key: const Key('tts-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用朗读'),
                  subtitle: const Text('关掉只停用「自动朗读回复」；手动点喇叭照样会读'),
                  value: _ttsEnabled,
                  onChanged: (value) => setState(() => _ttsEnabled = value),
                ),
                TextField(
                  key: const Key('tts-base-url'),
                  controller: _ttsBaseUrl,
                  decoration: const InputDecoration(
                    labelText: '语音服务地址',
                    hintText: 'http://127.0.0.1:8766',
                    helperText: 'chino-tts 或 GPT-SoVITS api_v2；根路径 404 是正常的',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('tts-voice'),
                  controller: _ttsVoice,
                  decoration: const InputDecoration(
                    labelText: '音色',
                    helperText: '点下面的预设，或自己填服务里的音色名；'
                        'zhino / xiaoyi 走在线合成，几乎实时，'
                        'zhino-clone 是本机克隆，比实时慢很多',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final preset in TtsConfig.voicePresets)
                      ActionChip(
                        key: Key('tts-voice-$preset'),
                        label: Text(preset),
                        onPressed: () =>
                            setState(() => _ttsVoice.text = preset),
                      ),
                  ],
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
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
