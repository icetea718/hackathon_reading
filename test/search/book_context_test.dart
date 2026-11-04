import 'package:flutter_test/flutter_test.dart';

import 'package:coread/distill/distill_digest.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/search/book_context.dart';

final book = Book(
  id: 'b1',
  title: '瓦尔登湖',
  author: '梭罗',
  format: BookFormat.epub,
  sourcePath: '/books/walden.epub',
  addedAt: DateTime(2026, 1, 1),
);

Chapter chapter(int index, String title) => Chapter(
      id: 'c$index',
      bookId: 'b1',
      index: index,
      title: title,
      startOffset: 0,
      endOffset: 0,
      contentText: '',
    );

class FakeDigests implements DistillDigestSource {
  FakeDigests(this.digest);

  final DistillDigest? digest;

  @override
  Future<DistillDigest?> load(String bookId) async => digest;
}

final digest = DistillDigest(
  oneLiner: '一个人在林子里住两年。',
  synopsis: '梭罗在瓦尔登湖边自建小屋，记录四季与思考。',
  themes: ['简朴', '自然'],
  gists: {
    0: '作者搬进小木屋，算了一笔盖房开销。',
    1: '湖边冬天的冰层厚度与访客。',
  },
  cards: [
    DistillDigestCard(
      slug: 'simplicity',
      title: '简朴生活',
      definition: '把生活的必需品压到最低。',
      sourceChapters: [0],
      quote: '我到林中去，是因为我希望从容地生活。',
    ),
  ],
);

BookContextBuilder builder({
  Book? bookOverride,
  List<Chapter>? chapters,
  DistillDigest? digestOverride,
  Map<int, String> texts = const {},
}) {
  return BookContextBuilder(
    loadBook: (_) async => bookOverride,
    loadChapters: (_) async => chapters ?? [chapter(0, '经济'), chapter(1, '冬天的湖')],
    loadChapterText: (_, index) async => texts[index],
    digests: FakeDigests(digestOverride),
  );
}

void main() {
  test('brief carries the one-liner, chapter map and key points', () async {
    final context = await builder(bookOverride: book, digestOverride: digest)
        .build('b1');

    expect(context, isNotNull);
    expect(context!.distilled, isTrue);
    expect(context.displayTitle, '《瓦尔登湖》梭罗');
    expect(context.brief, contains('一句话：一个人在林子里住两年。'));
    expect(context.brief, contains('第 1 章 经济：作者搬进小木屋'));
    expect(context.brief, contains('简朴生活'));
    expect(context.brief, contains('我到林中去'));
  });

  test('an undistilled book still names its chapters', () async {
    final context = await builder(bookOverride: book).build('b1');

    expect(context, isNotNull);
    expect(context!.distilled, isFalse);
    expect(context.brief, contains('还没有蒸馏'));
    expect(context.brief, contains('第 2 章 冬天的湖'));
    expect(context.excerpts, isEmpty);
  });

  test('the question decides which chapters are quoted', () async {
    final context = await builder(
      bookOverride: book,
      digestOverride: digest,
      texts: {0: '盖房花了二十八块一毛二。', 1: '冰层有二十二英寸厚。'},
    ).build('b1', question: '冰层多厚？');

    expect(context!.excerpts, hasLength(1));
    expect(context.excerpts.single.chapterIndex, 1);
    expect(context.excerpts.single.label, '第 2 章 冬天的湖');
    expect(context.excerpts.single.text, contains('二十二英寸'));
  });

  test('a question that matches nothing quotes nothing', () async {
    final context = await builder(
      bookOverride: book,
      digestOverride: digest,
      texts: {0: 'x', 1: 'y'},
    ).build('b1', question: '量子力学');

    expect(context!.excerpts, isEmpty);
  });

  test('a missing book yields null', () async {
    final context = await builder().build('gone');
    expect(context, isNull);
  });
}
