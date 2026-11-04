import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/features/companion/companion_quotes.dart';

void main() {
  group('composeCompanionMessage', () {
    test('returns the message unchanged without quotes', () {
      expect(composeCompanionMessage(const [], '这一段什么意思？'), '这一段什么意思？');
    });

    test('prefixes a single-line quote and separates it from the question', () {
      expect(
        composeCompanionMessage(const ['老牛回过头。'], '这句话说明了什么？'),
        '【引用】\n> 老牛回过头。\n\n这句话说明了什么？',
      );
    });

    test('prefixes every line of a multi-line quote', () {
      expect(
        composeCompanionMessage(const ['第一句。\n第二句。'], '继续'),
        '【引用】\n> 第一句。\n> 第二句。\n\n继续',
      );
    });

    test('joins several quotes into one quoted block', () {
      expect(
        composeCompanionMessage(const ['甲', '乙'], '问题'),
        '【引用】\n> 甲\n> 乙\n\n问题',
      );
    });

    test('ignores blank quotes', () {
      expect(
        composeCompanionMessage(const ['  ', '乙'], '问题'),
        '【引用】\n> 乙\n\n问题',
      );
    });
  });

  group('parseCompanionMessage', () {
    test('returns plain messages untouched', () {
      final parsed = parseCompanionMessage('福贵为什么败家？');
      expect(parsed.quote, isNull);
      expect(parsed.body, '福贵为什么败家？');
    });

    test('extracts the quoted block and the question', () {
      final parsed = parseCompanionMessage('【引用】\n> 甲\n> 乙\n\n问题');
      expect(parsed.quote, '甲\n乙');
      expect(parsed.body, '问题');
    });

    test('round-trips a multi-line quote with a multi-line question', () {
      const question = '为什么？\n还有别的吗？';
      final composed = composeCompanionMessage(
        const ['第一句。\n第二句。'],
        question,
      );
      final parsed = parseCompanionMessage(composed);
      expect(parsed.quote, '第一句。\n第二句。');
      expect(parsed.body, question);
    });
  });

  group('companionQuotesProvider', () {
    test('adds, removes and clears pending quotes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final quotes = container.read(companionQuotesProvider.notifier);

      quotes.add('甲');
      quotes.add('乙');
      expect(container.read(companionQuotesProvider), ['甲', '乙']);

      quotes.removeAt(0);
      expect(container.read(companionQuotesProvider), ['乙']);

      quotes.clear();
      expect(container.read(companionQuotesProvider), isEmpty);
    });
  });
}
