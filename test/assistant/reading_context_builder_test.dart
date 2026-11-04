import 'package:flutter_test/flutter_test.dart';
import 'package:coread/assistant/reading_context_builder.dart';

void main() {
  test('assembles book, chapter and selection fields', () {
    final builder = ReadingContextBuilder();

    final context = builder.build(
      bookTitle: '围城',
      author: '钱钟书',
      chapterTitle: '第一章',
      chapterText: '方鸿渐是留学生。',
      selectedText: '方鸿渐',
    );

    expect(context.bookTitle, '围城');
    expect(context.author, '钱钟书');
    expect(context.chapterTitle, '第一章');
    expect(context.chapterText, '方鸿渐是留学生。');
    expect(context.selectedText, '方鸿渐');
  });

  test('missing author and chapter become empty strings', () {
    final builder = ReadingContextBuilder();

    final context = builder.build(bookTitle: '无题', chapterText: '正文');

    expect(context.author, '');
    expect(context.chapterTitle, '');
    expect(context.selectedText, '');
  });

  test('truncates chapter text to the configured limit', () {
    final builder = ReadingContextBuilder(maxChapterChars: 5);

    final context = builder.build(
      bookTitle: '书',
      chapterText: '一二三四五六七八',
    );

    expect(context.chapterText, '一二三四五');
  });

  test('keeps chapter text unchanged when it fits', () {
    final builder = ReadingContextBuilder(maxChapterChars: 10);

    final context = builder.build(bookTitle: '书', chapterText: '一二三四五');

    expect(context.chapterText, '一二三四五');
  });

  test('does not truncate the selected text', () {
    final builder = ReadingContextBuilder(maxChapterChars: 2);

    final context = builder.build(
      bookTitle: '书',
      chapterText: '正文很长',
      selectedText: '选中的完整句子',
    );

    expect(context.chapterText, '正文');
    expect(context.selectedText, '选中的完整句子');
  });

  test('rejects a non-positive chapter limit', () {
    expect(
      () => ReadingContextBuilder(maxChapterChars: 0),
      throwsArgumentError,
    );
  });
}
