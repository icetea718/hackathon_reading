import 'package:flutter_test/flutter_test.dart';
import 'package:coread/search/bigrams.dart';

void main() {
  test('去标点、转小写、相邻两字符一组', () {
    expect(bigrams('雨，Rain 2024'), {
      '雨r', 'ra', 'ai', 'in', 'n2', '20', '02', '24',
    });
  });

  test('单个字符没有 bigram', () {
    expect(bigrams('雨'), isEmpty);
  });

  test('空串与纯标点返回空集合', () {
    expect(bigrams(''), isEmpty);
    expect(bigrams('，。！？ —'), isEmpty);
  });

  test('相邻两字不重复时才只算一个词元', () {
    expect(bigrams('雨雨雨'), {'雨雨'});
  });
}
