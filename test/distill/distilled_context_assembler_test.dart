import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/distill/distill_digest.dart';
import 'package:hackathon_reading/distill/distilled_context_assembler.dart';

void main() {
  final chapterText = List.generate(400, (i) => '第$i段落：福贵在田里干活。').join('\n');

  test('windowedExcerpt keeps the anchor inside a 4000 char window', () {
    final excerpt = windowedExcerpt(chapterText, charOffset: 18000);

    expect(excerpt.length, lessThanOrEqualTo(4000));
    expect(excerpt.contains('福贵'), isTrue);
  });

  test('windowedExcerpt falls back to the chapter head without an anchor', () {
    final excerpt = windowedExcerpt(chapterText);

    expect(excerpt.length, lessThanOrEqualTo(4000));
    expect(excerpt.startsWith('第0段落'), isTrue);
  });

  test('assemble includes overview, tone, neighbour gists and cards', () {
    final digest = DistillDigest(
      oneLiner: '一个人一生的苦难',
      synopsis: '福贵从富家少爷变成孤身老人。',
      themes: const ['活着'],
      toneOverall: '克制的悲悯',
      toneStyle: const ['白描'],
      gists: const {1: '福贵被抓壮丁', 2: '福贵回家', 3: '家珍病倒'},
      cards: const [
        DistillDigestCard(
          slug: 'loss',
          title: '败家',
          definition: '福贵把家产输光',
          sourceChapters: [2],
          quote: '我年轻的时候真是个败家子',
        ),
        DistillDigestCard(
          slug: 'war',
          title: '战争',
          definition: '被抓壮丁',
          sourceChapters: [5],
        ),
        DistillDigestCard(
          slug: 'home',
          title: '回家',
          definition: '回到茅屋',
          sourceChapters: [2],
        ),
        DistillDigestCard(
          slug: 'ox',
          title: '老牛',
          definition: '和老牛说话',
          sourceChapters: [2],
        ),
      ],
    );

    final assembled = DistilledContextAssembler().assemble(
      AssembleInput(
        bookId: 'book-1',
        bookTitle: '活着',
        author: '余华',
        chapterIndex: 2,
        chapterTitle: '第二章',
        chapterText: chapterText,
        chapterCharOffset: 18000,
        question: '福贵为什么把家产输光了？',
      ),
      digest,
    );

    expect(assembled.brief, contains('一个人一生的苦难'));
    expect(assembled.brief, contains('克制的悲悯'));
    expect(assembled.brief, contains('福贵被抓壮丁'));
    expect(assembled.brief, contains('第 3 章'));
    expect(assembled.brief, contains('不要引用后面的章节'));
    expect(assembled.brief.length, lessThanOrEqualTo(1500));
    expect(assembled.usedChars, lessThanOrEqualTo(1500 + 4000));
    expect(assembled.chapterExcerpt.length, lessThanOrEqualTo(4000));
  });

  test('cards from the current chapter outrank far ones and cap at three', () {
    final digest = DistillDigest(
      oneLiner: 'x',
      cards: const [
        DistillDigestCard(
          slug: 'far',
          title: '远处的事',
          definition: 'd',
          sourceChapters: [9],
        ),
        DistillDigestCard(
          slug: 'near',
          title: '眼前的事',
          definition: 'd',
          sourceChapters: [1],
        ),
        DistillDigestCard(
          slug: 'near2',
          title: '眼前的事二',
          definition: 'd',
          sourceChapters: [1],
        ),
        DistillDigestCard(
          slug: 'near3',
          title: '眼前的事三',
          definition: 'd',
          sourceChapters: [1],
        ),
      ],
    );

    final assembled = DistilledContextAssembler().assemble(
      AssembleInput(
        bookId: 'b',
        bookTitle: 't',
        chapterIndex: 1,
        chapterText: '正文',
      ),
      digest,
    );

    expect(assembled.brief, contains('眼前的事'));
    expect(assembled.brief, isNot(contains('远处的事')));
  });

  test('an empty digest still yields a usable brief', () {
    final assembled = DistilledContextAssembler().assemble(
      const AssembleInput(
        bookId: 'b',
        bookTitle: '活着',
        chapterIndex: 0,
        chapterTitle: '第一章',
        chapterText: '正文',
      ),
      const DistillDigest(),
    );

    expect(assembled.brief, contains('第一章'));
    expect(assembled.chapterExcerpt, '正文');
  });
}
