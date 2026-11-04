enum ReaderSpread { single, double }

const double kSpreadMinWidth = 880;
const double kSpreadContentMaxWidth = 1320;
const double kSpreadGutterWidth = 24;
const double kPaneHorizontalPadding = 20;

ReaderSpread readerSpreadFromName(String? name) {
  return switch (name) {
    'single' => ReaderSpread.single,
    'double' => ReaderSpread.double,
    _ => ReaderSpread.double,
  };
}

bool spreadApplies(ReaderSpread spread, double availableWidth) {
  return spread == ReaderSpread.double && availableWidth >= kSpreadMinWidth;
}

int spreadPageIndex(int pageIndex) {
  return pageIndex - pageIndex % 2;
}

int spreadLastPageIndex(int pageIndex, int pageCount) {
  if (pageCount <= 0) return 0;
  return (spreadPageIndex(pageIndex) + 1).clamp(0, pageCount - 1);
}

int spreadCount(int pageCount) {
  return pageCount <= 0 ? 0 : (pageCount + 1) ~/ 2;
}

double spreadTextWidth(double availableWidth) {
  final contentWidth = availableWidth.clamp(0.0, kSpreadContentMaxWidth);
  return (contentWidth - kSpreadGutterWidth) / 2 - kPaneHorizontalPadding * 2;
}
