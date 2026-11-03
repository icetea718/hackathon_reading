import 'distill_digest.dart';

/// Everything the companion knows about the reader's current position.
class AssembleInput {
  const AssembleInput({
    required this.bookId,
    required this.bookTitle,
    this.author = '',
    this.chapterIndex = 0,
    this.chapterTitle = '',
    this.chapterText = '',
    this.chapterCharOffset,
    this.question = '',
  });

  final String bookId;
  final String bookTitle;
  final String author;
  final int chapterIndex;
  final String chapterTitle;
  final String chapterText;
  final int? chapterCharOffset;
  final String question;
}

/// The distilled prompt scaffold plus the chapter window actually sent.
class AssembledContext {
  const AssembledContext({
    required this.brief,
    required this.chapterExcerpt,
    required this.usedChars,
  });

  final String brief;
  final String chapterExcerpt;
  final int usedChars;
}

/// Picks the most relevant slice of a long chapter around the reading anchor.
String windowedExcerpt(
  String text, {
  int? charOffset,
  int head = 800,
  int around = 2400,
  int tail = 800,
}) {
  final max = head + around + tail;
  if (text.length <= max) return text;
  if (charOffset == null || charOffset <= 0) return text.substring(0, max);

  var start = charOffset - head - around ~/ 2;
  if (start < 0) start = 0;
  if (start + max > text.length) start = text.length - max;
  return text.substring(start, start + max);
}

/// Turns a [DistillDigest] into a compact system-prompt preamble so the model
/// understands the whole book without receiving the whole book.
class DistilledContextAssembler {
  const DistilledContextAssembler({
    this.maxBriefChars = 1200,
    this.maxToneChars = 300,
    this.maxChapterChars = 4000,
    this.maxGistChars = 60,
    this.maxCards = 3,
    this.cardChars = 250,
  });

  final int maxBriefChars;
  final int maxToneChars;
  final int maxChapterChars;
  final int maxGistChars;
  final int maxCards;
  final int cardChars;

  AssembledContext assemble(AssembleInput input, DistillDigest digest) {
    final buffer = StringBuffer();
    final budget = maxBriefChars + maxToneChars;

    void add(String text) {
      final room = budget - buffer.length;
      if (room <= 0) return;
      buffer.write(text.length <= room ? text : text.substring(0, room));
    }

    add('【全书】《${input.bookTitle}》${input.author.isEmpty ? '' : input.author}\n');
    if (digest.oneLiner.isNotEmpty) add('一句话：${digest.oneLiner}\n');
    if (digest.synopsis.isNotEmpty) {
      add('梗概：${_clip(digest.synopsis, 400)}\n');
    }
    if (digest.themes.isNotEmpty) {
      add('主题：${digest.themes.take(5).join('、')}\n');
    }

    if (digest.toneOverall.isNotEmpty || digest.toneStyle.isNotEmpty) {
      final tone = StringBuffer('【语气】');
      if (digest.toneOverall.isNotEmpty) {
        tone.write('整体 ${_clip(digest.toneOverall, maxToneChars)}');
      }
      if (digest.toneStyle.isNotEmpty) {
        tone.write('${tone.length > 3 ? '；' : ''}文风 ${digest.toneStyle.take(3).join('、')}');
      }
      add('$tone\n');
    }

    add('【当前章节】第 ${input.chapterIndex + 1} 章 ${input.chapterTitle}\n');

    final nearby = <int>[
      input.chapterIndex - 1,
      input.chapterIndex,
      input.chapterIndex + 1,
    ].where(digest.gists.containsKey).toList();
    if (nearby.isNotEmpty) {
      add('【章节地图】\n');
      for (final index in nearby) {
        add('第 ${index + 1} 章：${_clip(digest.gists[index]!, maxGistChars)}\n');
      }
    }

    final cards = _rankCards(digest.cards, input);
    if (cards.isNotEmpty) {
      add('【本书要点】\n');
      for (final card in cards) {
        final quote = card.quote == null ? '' : '（原文：${_clip(card.quote!, 80)}）';
        add('- ${card.title}：${_clip(card.definition, cardChars)}$quote\n');
      }
    }

    add('【提示】只依据截至第 ${input.chapterIndex + 1} 章的内容作答；'
        '不要引用后面的章节，也不要提前透露后续情节。');

    final excerpt = windowedExcerpt(
      input.chapterText,
      charOffset: input.chapterCharOffset,
      around: maxChapterChars - 1600,
    );

    return AssembledContext(
      brief: buffer.toString(),
      chapterExcerpt: excerpt,
      usedChars: buffer.length + excerpt.length,
    );
  }

  List<DistillDigestCard> _rankCards(
    List<DistillDigestCard> cards,
    AssembleInput input,
  ) {
    final questionTerms = _terms(input.question);
    final questionBigrams = _bigrams(input.question);

    final scored = cards.map((card) {
      final cardTerms = _terms('${card.title}${card.definition}');
      final overlap = cardTerms.where(questionTerms.contains).length;
      final onChapter = card.sourceChapters.contains(input.chapterIndex) ? 1 : 0;
      final bigramHits = _bigrams('${card.title}${card.definition}')
          .where(questionBigrams.contains)
          .length;
      return (
        card: card,
        score: 3 * overlap + 2 * onChapter + bigramHits,
      );
    }).toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final aFirst = a.card.sourceChapters.isEmpty ? 1 << 30 : a.card.sourceChapters.first;
        final bFirst = b.card.sourceChapters.isEmpty ? 1 << 30 : b.card.sourceChapters.first;
        final byChapter = aFirst.compareTo(bFirst);
        if (byChapter != 0) return byChapter;
        return a.card.slug.compareTo(b.card.slug);
      });

    return scored.take(maxCards).map((e) => e.card).toList();
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  static Set<String> _terms(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]'), ' ');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2)
        .toSet();
  }

  static Set<String> _bigrams(String text) {
    final chars = text.replaceAll(RegExp(r'\s+'), '').runes.toList();
    final grams = <String>{};
    for (var i = 0; i + 1 < chars.length; i++) {
      grams.add(String.fromCharCodes([chars[i], chars[i + 1]]));
    }
    return grams;
  }
}
