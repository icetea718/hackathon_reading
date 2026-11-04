import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../distill/llm/llm_client.dart';
import '../distill/llm/openai_llm_client.dart';
import 'ark_image_client.dart';
import 'illustration_config.dart';
import 'illustration_models.dart';
import 'illustration_prompt.dart';

/// 一次插画生成的完整流程：文字 -> 方案 -> 草图 -> 上色。
class IllustrationService {
  IllustrationService({
    required IllustrationEffective effective,
    LlmClient? llmClient,
    ArkImageClient? imageClient,
  })  : effective = effective,
        _llm = llmClient ??
            OpenAiLlmClient(
              config: () => effective.chatConfig,
              requestTimeout: const Duration(seconds: 180),
            ),
        _image = imageClient ??
            ArkImageClient(
              baseUrl: effective.baseUrl,
              apiKey: effective.apiKey,
              model: effective.imageModel,
              requestTimeout: const Duration(seconds: 300),
            );

  final IllustrationEffective effective;
  final LlmClient _llm;
  final ArkImageClient _image;

  static const maxInputChars = 6000;

  Future<IllustrationResult> generate(
    String text, {
    void Function(IllustrationStage stage)? onStage,
  }) async {
    final input = text.trim();
    if (input.isEmpty) {
      throw IllustrationException('请先填入要生成插画的小说段落。');
    }
    if (!effective.isConfigured) {
      throw IllustrationException(
        '还没有配置插画服务。请到「设置 → 插画」填写生图接口地址、API Key 和图像模型。',
      );
    }
    if (effective.isDeepSeek) {
      throw IllustrationException(
        '当前插画接口是 DeepSeek，它不支持生图。请把插画接口改成支持生图的接口地址。',
      );
    }

    onStage?.call(IllustrationStage.planning);
    final raw = await _llm.completeJson([
      const LlmMessage(LlmRole.system, illustrationSystemPrompt),
      LlmMessage(
        LlmRole.user,
        input.length <= maxInputChars
            ? input
            : input.substring(0, maxInputChars),
      ),
    ]);
    final plan = parseIllustrationPlan(raw);

    onStage?.call(IllustrationStage.sketching);
    final sketchBytes = await _image.generate(prompt: plan.sketchPrompt);
    final directory = await _tempDirectory();
    final sketchFile = File(p.join(directory.path, 'sketch.png'));
    await sketchFile.writeAsBytes(sketchBytes, flush: true);

    onStage?.call(IllustrationStage.coloring);
    final finalBytes = await _image.generate(
      prompt: plan.colorPrompt,
      referenceImage: sketchBytes,
    );
    final finalFile = File(p.join(directory.path, 'final.png'));
    await finalFile.writeAsBytes(finalBytes, flush: true);

    return IllustrationResult(
      plan: plan,
      sketchFile: sketchFile,
      finalFile: finalFile,
    );
  }

  Future<Directory> _tempDirectory() async {
    final base = await getTemporaryDirectory();
    final directory = Directory(
      p.join(base.path, 'illustration', const Uuid().v4()),
    );
    await directory.create(recursive: true);
    return directory;
  }

  void dispose() {
    _llm.dispose();
    _image.dispose();
  }
}
