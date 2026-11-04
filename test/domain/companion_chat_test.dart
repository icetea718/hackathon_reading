import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';

void main() {
  test('a short first message becomes the thread title unchanged', () {
    expect(companionThreadTitle('  福贵为什么败家？  '), '福贵为什么败家？');
  });

  test('a long first message is cut at sixteen characters', () {
    final title = companionThreadTitle('一二三四五六七八九十一二三四五六七八九十');
    expect(title, '一二三四五六七八九十一二三四五六…');
    expect(title, endsWith('…'));
  });

  test('sixteen characters exactly are not cut', () {
    const text = '一二三四五六七八九十一二三四五六';
    expect(companionThreadTitle(text), text);
  });
}
