import 'package:flutter_test/flutter_test.dart';
import 'package:coread/features/reader/reader_spread.dart';

void main() {
  test('defaults to double and rejects unknown values', () {
    expect(readerSpreadFromName(null), ReaderSpread.double);
    expect(readerSpreadFromName('single'), ReaderSpread.single);
    expect(readerSpreadFromName('double'), ReaderSpread.double);
    expect(readerSpreadFromName('triple'), ReaderSpread.double);
  });

  test('applies double only at or above 880 logical pixels', () {
    expect(spreadApplies(ReaderSpread.double, 879.9), isFalse);
    expect(spreadApplies(ReaderSpread.double, 880), isTrue);
    expect(spreadApplies(ReaderSpread.single, 1400), isFalse);
  });

  test('snaps pages to the left of a spread', () {
    expect(spreadPageIndex(0), 0);
    expect(spreadPageIndex(3), 2);
    expect(spreadPageIndex(4), 4);
  });

  test('reports the right page and spread count', () {
    expect(spreadLastPageIndex(2, 5), 3);
    expect(spreadLastPageIndex(4, 5), 4);
    expect(spreadLastPageIndex(0, 1), 0);
    expect(spreadCount(3), 2);
    expect(spreadCount(4), 2);
    expect(spreadCount(0), 0);
  });

  test('computes the pane text width', () {
    expect(spreadTextWidth(1400), 608);
    expect(spreadTextWidth(880), 388);
  });
}
