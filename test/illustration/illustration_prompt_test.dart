import 'package:flutter_test/flutter_test.dart';
import 'package:coread/illustration/illustration_models.dart';
import 'package:coread/illustration/illustration_prompt.dart';

void main() {
  test('parses the standard three-line output', () {
    final plan = parseIllustrationPlan(
      '【媒介选择】：水彩淡彩\n'
      '【草图prompt】：雨夜老巷，单色线稿\n'
      '【上色prompt（图生图）】：低饱和冷灰，水彩晕染',
    );

    expect(plan.medium, '水彩淡彩');
    expect(plan.sketchPrompt, '雨夜老巷，单色线稿');
    expect(plan.colorPrompt, '低饱和冷灰，水彩晕染');
  });

  test('tolerates bold, backticks, spaces and half-width brackets', () {
    final plan = parseIllustrationPlan(
      '**【媒介选择】**：厚涂油画\n'
      '**【草图 prompt】**：`雪地里的男孩`\n'
      '[上色 prompt（图生图）]: **暖黄，厚涂笔触**',
    );

    expect(plan.medium, '厚涂油画');
    expect(plan.sketchPrompt, '雪地里的男孩');
    expect(plan.colorPrompt, '暖黄，厚涂笔触');
  });

  test('joins multi-line prompt bodies into one line', () {
    final plan = parseIllustrationPlan(
      '【媒介选择】：淡彩素描\n'
      '【草图prompt】：\n第一行场景\n第二行\n'
      '【上色prompt（图生图）】：\n冷灰色\n少量颜色',
    );

    expect(plan.sketchPrompt, '第一行场景 第二行');
    expect(plan.colorPrompt, '冷灰色 少量颜色');
  });

  test('throws when the output is a refusal or misses a field', () {
    expect(
      () => parseIllustrationPlan('【我仅用于小说文本转手绘插画，请输入小说段落】'),
      throwsA(isA<IllustrationException>()),
    );
    expect(
      () => parseIllustrationPlan('【媒介选择】：水彩\n【草图prompt】：只有草图'),
      throwsA(isA<IllustrationException>()),
    );
  });
}
