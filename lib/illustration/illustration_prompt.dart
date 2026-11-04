import 'illustration_models.dart';

/// 小说段落 -> 插画方案的策划提示词。
///
/// 与独立 Python 版保持一致：只输出“媒介 / 草图 / 上色”三行，每个
/// prompt 单行，画面克制，手绘质感，不要文字水印。
const String illustrationSystemPrompt = r'''你是一个小说插画策划师，你只有一个任务：把用户发来的小说段落转化为适合手绘风格的纪念插画方案。
你不能回答别的问题，不能写代码、不能聊天、不能总结小说剧情给用户，也不能做任何额外解释；超出“插画策划”的任务一律回复：【我仅用于小说文本转手绘插画，请输入小说段落】。

工作流程严格遵守：
1. 仔细阅读文段，抓取核心情绪、核心意象、光影、氛围，忽略不重要的细碎细节，画面要克制，不要塞满元素；
2. 自主选择合适的绘画媒介：水彩 / 淡彩素描 / 厚涂油画 / 水粉。选择逻辑：忧伤静谧用水彩淡彩；温暖厚重的场景用油画；干净清冷场景用素描淡彩；
3. 分两步输出绘图指令，每个 prompt 只写一行，不要换行：
  A. 线稿阶段prompt：只生成干净手绘草图、轮廓，线条自然，不要上色、不要光影渲染，适合真人手绘起稿；画幅为竖幅 3:4；
  B. 上色阶段prompt：基于上面这个草图上色，严格保持草图的构图、人物姿态和画幅不变，只做上色与质感；色彩数量尽量少，低饱和度，避免艳丽、塑料感、光滑AI质感；保留手绘笔触，笔触明显，像手工绘画，不要超写实真人照片风；
4. 输出格式固定，只输出下面三行，不要任何多余内容：
【媒介选择】：xxx
【草图prompt】：xxx
【上色prompt（图生图）】：xxx
禁止生成照片风、超写实人像，拒绝完美光滑皮肤、过度细节。画面内不要出现任何文字、签名、水印、边框。追求朴素、有纪念感的手绘插画。''';

final RegExp _planLabelPattern = RegExp(
  r'[【\[]\s*(媒介选择|草图\s*prompt|上色\s*prompt[^】\]]*)\s*[】\]]\s*\**\s*[:：]?\s*',
  caseSensitive: false,
);

/// 解析模型输出，兼容加粗、反引号、半角括号、全半角冒号和多行内容。
IllustrationPlan parseIllustrationPlan(String raw) {
  final matches = _planLabelPattern.allMatches(raw).toList();
  var medium = '';
  var sketch = '';
  var color = '';

  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final label = match.group(1)!.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final end = i + 1 < matches.length ? matches[i + 1].start : raw.length;
    final value = _cleanField(raw.substring(match.end, end));

    if (label == '媒介选择') {
      medium = value;
    } else if (label.startsWith('草图')) {
      sketch = value;
    } else if (label.startsWith('上色')) {
      color = value;
    }
  }

  if (sketch.isEmpty || color.isEmpty) {
    throw IllustrationException(
      '模型输出格式不对，没有拿到完整的草图和上色指令。',
    );
  }
  return IllustrationPlan(
    medium: medium,
    sketchPrompt: sketch,
    colorPrompt: color,
  );
}

String _cleanField(String value) {
  final withoutMarks = value.replaceAll('`', '').replaceAll('**', '');
  final collapsed = withoutMarks.replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed.replaceAll(RegExp(r'^\*+|\*+$'), '').trim();
}
