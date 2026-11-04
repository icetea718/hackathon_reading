import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/persona.dart';
import 'package:hackathon_reading/assistant/digest_aware_assistant_service.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/distill/distill_digest.dart';

class _RecordingService implements AssistantService {
  final List<ReadingContext> chats = [];
  final List<ReadingContext> summaries = [];

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage, {
    PersonaMode persona = PersonaMode.fallback,
  }) async* {
    chats.add(context);
    yield '好的';
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) async* {
    summaries.add(context);
    yield '总结';
  }

  @override
  Stream<String> explain(
    String text, {
    required ReadingContext context,
  }) async* {
    yield '解释';
  }

  @override
  Stream<String> translate(String text, {required String targetLang}) async* {
    yield '翻译';
  }
}

class _FixedSource implements DistillDigestSource {
  _FixedSource(this.digest);

  final DistillDigest? digest;

  @override
  Future<DistillDigest?> load(String bookId) async => digest;
}

void main() {
  final longChapter = List.generate(200, (i) => '第$i段：福贵在田里。').join('\n');

  ReadingContext context() => ReadingContext(
        bookTitle: '活着',
        author: '余华',
        chapterTitle: '第二章',
        chapterText: longChapter,
        bookId: 'book-1',
        chapterIndex: 2,
        chapterCharOffset: 3000,
        allowSpoilers: true,
      );

  test('chat receives the distilled brief and a windowed chapter', () async {
    final inner = _RecordingService();
    final service = DigestAwareAssistantService(
      inner: inner,
      source: _FixedSource(const DistillDigest(oneLiner: '一个人一生的苦难')),
    );

    await service.chat(context(), const [], '福贵为什么败家？').toList();

    final sent = inner.chats.single;
    expect(sent.bookBrief, contains('一个人一生的苦难'));
    expect(sent.chapterText.length, lessThanOrEqualTo(4000));
  });

  test('summarizeChapter keeps the whole chapter', () async {
    final inner = _RecordingService();
    final service = DigestAwareAssistantService(
      inner: inner,
      source: _FixedSource(const DistillDigest(oneLiner: 'x')),
    );

    await service.summarizeChapter(context()).toList();

    expect(inner.summaries.single.chapterText, longChapter);
  });

  test('without a digest the context passes through untouched', () async {
    final inner = _RecordingService();
    final service = DigestAwareAssistantService(
      inner: inner,
      source: _FixedSource(null),
    );

    await service.chat(context(), const [], '你好').toList();

    final sent = inner.chats.single;
    expect(sent.bookBrief, '');
    expect(sent.chapterText, longChapter);
  });

  const guarded = ReadingContext(
    bookTitle: '活着',
    chapterTitle: '第二章',
    chapterText: '开头前文。当前页内容。当前页之后的后文。',
    bookId: 'book-1',
    chapterIndex: 2,
    pageStartOffset: 5,
    pageEndOffset: 11,
    currentPageText: '当前页内容。',
  );

  test('chat hides text after the page while spoilers are off', () async {
    final inner = _RecordingService();
    final service = DigestAwareAssistantService(
      inner: inner,
      source: _FixedSource(const DistillDigest(oneLiner: 'x')),
    );

    await service.chat(guarded, const [], '这一页讲了什么？').toList();

    final sent = inner.chats.single;
    expect(sent.allowSpoilers, isFalse);
    expect(sent.chapterText, contains('开头前文'));
    expect(sent.chapterText, isNot(contains('后文')));
  });

  test('allowing spoilers restores the text after the page', () async {
    final inner = _RecordingService();
    final service = DigestAwareAssistantService(
      inner: inner,
      source: _FixedSource(const DistillDigest(oneLiner: 'x')),
    );

    await service.chat(
      guarded.copyWith(allowSpoilers: true),
      const [],
      '后面发生了什么？',
    ).toList();

    final sent = inner.chats.single;
    expect(sent.allowSpoilers, isTrue);
    expect(sent.chapterText, contains('后文'));
  });

  test('chat without a digest also stops at the page', () async {
    final inner = _RecordingService();
    final service = DigestAwareAssistantService(
      inner: inner,
      source: _FixedSource(null),
    );

    await service.chat(guarded, const [], '这一页讲了什么？').toList();

    final sent = inner.chats.single;
    expect(sent.chapterText, contains('开头前文'));
    expect(sent.chapterText, isNot(contains('后文')));
  });

  test('summarizeChapter still receives the whole chapter', () async {
    final inner = _RecordingService();
    final service = DigestAwareAssistantService(
      inner: inner,
      source: _FixedSource(const DistillDigest(oneLiner: 'x')),
    );

    await service.summarizeChapter(guarded).toList();

    expect(inner.summaries.single.chapterText, guarded.chapterText);
  });
}
