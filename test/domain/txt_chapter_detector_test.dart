import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/services/txt_chapter_detector.dart';

void main() {
  test('detects Chinese and English headings with exact offsets', () {
    const text = '第一章 开始\n内容一\nChapter 2\nThe end';
    final chapters = detectTxtChapters(text);

    expect(chapters.map((c) => c.title), ['第一章 开始', 'Chapter 2']);
    expect(chapters[0].startOffset, 0);
    expect(chapters[0].endOffset, text.indexOf('Chapter 2'));
    expect(chapters[1].startOffset, text.indexOf('Chapter 2'));
    expect(chapters[1].endOffset, text.length);
  });

  test('creates a 前言 chapter for leading text', () {
    const text = '这是前言。\n第一章 开始\n内容';
    final chapters = detectTxtChapters(text);

    expect(chapters.map((c) => c.title), ['前言', '第一章 开始']);
    expect(chapters[0].startOffset, 0);
    expect(chapters[0].endOffset, text.indexOf('第一章'));
    expect(chapters[1].startOffset, text.indexOf('第一章'));
    expect(chapters[1].endOffset, text.length);
  });

  test('returns a single fallback chapter when no headings exist', () {
    const text = '只有普通的正文。\n没有任何章节标题。';
    final chapters = detectTxtChapters(text);

    expect(chapters.single.title, '正文');
    expect(chapters.single.startOffset, 0);
    expect(chapters.single.endOffset, text.length);
  });

  test('does not treat long prose starting with 第一章 as a heading', () {
    const text = '第一章就写到了主角的童年，这部分内容很长，而且是一句完整的话。\n第二段';
    final chapters = detectTxtChapters(text);
    expect(chapters.single.title, '正文');
    expect(chapters.single.startOffset, 0);
    expect(chapters.single.endOffset, text.length);
  });

  test('handles CRLF without shifting offsets', () {
    const text = '第一章 一\r\n内容\r\n第二章 二\r\n内容二';
    final chapters = detectTxtChapters(text);

    expect(chapters.map((c) => c.title), ['第一章 一', '第二章 二']);
    expect(chapters[1].startOffset, text.indexOf('第二章'));
    expect(chapters[1].endOffset, text.length);
  });

  test('detects parenthesized headings and 部分 variants', () {
    const text = '第一章（上）\n甲\n第一部分 开始\n乙\n第二部分：终\n丙';
    final chapters = detectTxtChapters(text);

    expect(chapters.map((c) => c.title), [
      '第一章（上）',
      '第一部分 开始',
      '第二部分：终',
    ]);
  });

  test('detects 番外 and 第123章 headings', () {
    const text = '第一章 开始\n甲\n番外 后日谈\n乙\n第123章 终\n丙';
    final chapters = detectTxtChapters(text);

    expect(chapters.map((c) => c.title), ['第一章 开始', '番外 后日谈', '第123章 终']);
    expect(chapters.last.endOffset, text.length);
  });

  test('returns no chapters for whitespace-only text', () {
    expect(detectTxtChapters(' \n\t '), isEmpty);
  });

  test('handles 2000 chapters without losing content', () {
    final buffer = StringBuffer();
    for (var i = 1; i <= 2000; i++) {
      buffer.writeln('第$i章 标题$i');
      buffer.writeln('正文$i');
    }
    final text = buffer.toString();
    final chapters = detectTxtChapters(text);

    expect(chapters, hasLength(2000));
    expect(chapters.first.startOffset, 0);
    expect(chapters.last.endOffset, text.length);
  });
}
