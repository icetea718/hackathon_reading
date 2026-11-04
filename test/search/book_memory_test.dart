import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/repositories/companion_chat_repository.dart';
import 'package:coread/domain/models/annotation.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/domain/models/companion_chat.dart';
import 'package:coread/search/book_memory.dart';

void main() {
  const chapters = [
    Chapter(
      id: 'c0',
      bookId: 'b1',
      index: 0,
      title: '经济',
      startOffset: 0,
      endOffset: 100,
      contentText: '',
    ),
    Chapter(
      id: 'c1',
      bookId: 'b1',
      index: 1,
      title: '冬天的湖',
      startOffset: 100,
      endOffset: 200,
      contentText: '',
    ),
  ];

  Book shelfBook({BookFormat format = BookFormat.epub, bool comic = false}) {
    return Book(
      id: 'b1',
      title: '瓦尔登湖',
      author: '梭罗',
      format: format,
      sourcePath: '/books/walden.${format.name}',
      comic: comic,
      addedAt: DateTime(2026, 1, 1),
    );
  }

  final time = DateTime(2026, 11, 4);
  var ids = 0;
  Annotation annotation({
    required AnnotationType type,
    String? chapterId,
    int anchorStart = 0,
    String selectedText = '',
    String noteText = '',
  }) {
    return Annotation(
      id: 'a${ids++}',
      bookId: 'b1',
      chapterId: chapterId,
      type: type,
      anchorStart: anchorStart,
      selectedText: selectedText,
      noteText: noteText,
      createdAt: time,
      updatedAt: time,
    );
  }

  CompanionThread thread(String id) {
    return CompanionThread(
      id: id,
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '经济',
      title: id,
      createdAt: time,
      updatedAt: time,
      messageCount: 2,
    );
  }

  BookMemoryBuilder builder({
    Book? book,
    List<Chapter> chapterList = chapters,
    List<Annotation> annotations = const [],
    List<CompanionThread> threads = const [],
    CompanionDigest digest = CompanionDigest.empty,
  }) {
    final shelf = book ?? shelfBook();
    return BookMemoryBuilder(
      loadBook: (id) async => id == shelf.id ? shelf : null,
      loadChapters: (id) async => chapterList,
      loadAnnotations: (id) async => annotations,
      loadThreads: (id) async => threads,
      loadDigest: (id, selection) async => digest,
    );
  }

  test('annotations are grouped by type and labeled by chapter', () async {
    final memory = await builder(
      annotations: [
        annotation(type: AnnotationType.bookmark, chapterId: 'c1'),
        annotation(
          type: AnnotationType.highlight,
          chapterId: 'c0',
          selectedText: '一个人住',
        ),
        annotation(
          type: AnnotationType.note,
          chapterId: 'c1',
          noteText: '这里很安静',
        ),
      ],
      threads: [thread('t1')],
    ).build('b1');

    expect(memory, isNotNull);
    expect(memory!.bookTitle, '瓦尔登湖');
    expect(memory.bookmarks.single.label, '第 2 章 冬天的湖');
    expect(memory.highlights.single.label, '第 1 章 经济');
    expect(memory.highlights.single.text, '一个人住');
    expect(memory.notes.single.text, '这里很安静');
    expect(memory.companionThreads.single.id, 't1');
    expect(memory.isEmpty, isFalse);
  });

  test('an annotation without a chapter falls back to the anchor percentage',
      () async {
    final memory = await builder(
      annotations: [
        annotation(
          type: AnnotationType.highlight,
          anchorStart: 150,
          selectedText: '湖结了冰',
        ),
      ],
    ).build('b1');

    expect(memory!.highlights.single.label, '第 2 章 冬天的湖 · 50%');
  });

  test('page-based books label annotations by page', () async {
    final pdf = await builder(
      book: shelfBook(format: BookFormat.pdf),
      annotations: [
        annotation(type: AnnotationType.bookmark, anchorStart: 7),
      ],
    ).build('b1');
    expect(pdf!.bookmarks.single.label, '第 7 页');

    final comic = await builder(
      book: shelfBook(comic: true),
      annotations: [
        annotation(
          type: AnnotationType.note,
          anchorStart: 3,
          noteText: '这一格好笑',
        ),
      ],
    ).build('b1');
    expect(comic!.notes.single.label, '第 3 页');
  });

  test('the prompt block caps bookmarks, highlights and notes', () async {
    final memory = await builder(
      annotations: [
        for (var i = 0; i < 35; i++)
          annotation(type: AnnotationType.bookmark, chapterId: 'c0'),
        for (var i = 0; i < 45; i++)
          annotation(
            type: AnnotationType.highlight,
            chapterId: 'c0',
            selectedText: '高$i',
          ),
        for (var i = 0; i < 35; i++)
          annotation(
            type: AnnotationType.note,
            chapterId: 'c0',
            noteText: '注$i',
          ),
      ],
    ).build('b1');

    final block = memory!.promptBlock();
    expect(block, contains('书签：'));
    expect(block, contains('高亮：'));
    expect(block, contains('笔记：'));
    expect('高0'.allMatches(block).length, 1);
    expect(block, isNot(contains('高44')));
    expect(block, isNot(contains('注34')));
    expect(block.length, lessThanOrEqualTo(BookMemory.maxPromptChars));
  });

  test('the prompt block stays within the character budget', () async {
    final memory = await builder(
      annotations: [
        for (var i = 0; i < 30; i++)
          annotation(
            type: AnnotationType.highlight,
            chapterId: 'c0',
            selectedText: '这' * 100,
          ),
      ],
      digest: CompanionDigest(
        text: '【经济】${'读' * 300}',
        threadIds: const {'t1'},
      ),
    ).build('b1');

    final block = memory!.promptBlock();
    expect(block.length, lessThanOrEqualTo(BookMemory.maxPromptChars));
  });

  test('the companion digest survives an annotation-heavy prompt', () async {
    final memory = await builder(
      annotations: [
        for (var i = 0; i < 40; i++)
          annotation(
            type: AnnotationType.highlight,
            chapterId: 'c0',
            selectedText: '这' * 100,
          ),
      ],
      digest: CompanionDigest(
        text: '【经济】${'读' * 1200}',
        threadIds: const {'t1'},
      ),
    ).build('b1');

    final block = memory!.promptBlock();
    expect(block, contains('【陪读对话摘要】'));
    expect(block, contains('读读读'));
    expect(block.length, lessThanOrEqualTo(BookMemory.maxPromptChars));
  });

  test('the prompt block carries the companion digest', () async {
    final memory = await builder(
      digest: const CompanionDigest(
        text: '【第一章】读者：福贵是谁？ 助手：地主家的少爷。',
        threadIds: {'t1'},
      ),
    ).build('b1');

    final block = memory!.promptBlock();
    expect(block, contains('【陪读对话摘要】'));
    expect(block, contains('地主家的少爷'));
  });

  test('nothing to remember yields an empty block', () async {
    final memory = await builder().build('b1');

    expect(memory!.isEmpty, isTrue);
    expect(memory.promptBlock(), isEmpty);
  });

  test('a book that no longer exists builds nothing', () async {
    expect(await builder().build('missing'), null);
  });
}
