import '../models/detected_chapter.dart';

final RegExp _headingPattern = RegExp(
  r'^(?:'
  r'第[0-9０-９一二三四五六七八九十百千万零两〇]+(?:[章节卷回篇集]|部(?:分)?)'
  r'(?:\s|[:：、.．\-—（(【\[]|$)'
  r'|(?:序章|楔子|引子|前言|序言|后记|尾声|番外|正文)'
  r'(?:\s|[:：、.．\-—（(【\[]|$)'
  r'|Chapter\s+[0-9IVXLC]+(?:\s|[:：.．\-（(【\[]|$)'
  r')',
  caseSensitive: false,
);

const List<String> _sentenceEnders = ['。', '！', '？', '；'];

List<DetectedChapter> detectTxtChapters(
  String text, {
  String fallbackTitle = '正文',
}) {
  if (text.trim().isEmpty) return const [];

  final headings = <DetectedChapter>[];
  var lineStart = 0;
  for (final rawLine in text.split('\n')) {
    var line = rawLine;
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    final trimmed = line.trim();
    if (trimmed.isNotEmpty &&
        trimmed.length <= 40 &&
        !_sentenceEnders.any(trimmed.endsWith) &&
        _headingPattern.hasMatch(trimmed)) {
      final leadingWhitespace = line.length - line.trimLeft().length;
      headings.add(DetectedChapter(
        title: trimmed,
        startOffset: lineStart + leadingWhitespace,
        endOffset: 0,
      ));
    }
    lineStart += rawLine.length + 1;
  }

  if (headings.isEmpty) {
    return [
      DetectedChapter(
        title: fallbackTitle,
        startOffset: 0,
        endOffset: text.length,
      ),
    ];
  }

  final chapters = <DetectedChapter>[];
  final firstStart = headings.first.startOffset;
  if (text.substring(0, firstStart).trim().isNotEmpty) {
    chapters.add(DetectedChapter(
      title: '前言',
      startOffset: 0,
      endOffset: firstStart,
    ));
  }

  for (var i = 0; i < headings.length; i++) {
    final heading = headings[i];
    chapters.add(DetectedChapter(
      title: heading.title,
      startOffset: heading.startOffset,
      endOffset:
          i + 1 < headings.length ? headings[i + 1].startOffset : text.length,
    ));
  }
  return chapters;
}
