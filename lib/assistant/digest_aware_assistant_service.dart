import '../distill/distill_digest.dart';
import '../distill/distilled_context_assembler.dart';
import 'assistant_service.dart';
import 'reading_context.dart';

/// Decorates an [AssistantService] so every request carries the book's
/// distilled digest and a chapter window around the reader's anchor.
class DigestAwareAssistantService implements AssistantService {
  DigestAwareAssistantService({
    required this.inner,
    required this.source,
    DistilledContextAssembler? assembler,
  }) : assembler = assembler ?? const DistilledContextAssembler();

  final AssistantService inner;
  final DistillDigestSource source;
  final DistilledContextAssembler assembler;

  @override
  bool get isConfigured => inner.isConfigured;

  @override
  Stream<String> translate(String text, {required String targetLang}) =>
      inner.translate(text, targetLang: targetLang);

  @override
  Stream<String> explain(String text, {required ReadingContext context}) async* {
    final enriched = await _enrich(context, question: text, windowChapter: true);
    yield* inner.explain(text, context: enriched);
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) async* {
    final enriched = await _enrich(context, windowChapter: false);
    yield* inner.summarizeChapter(enriched);
  }

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage,
  ) async* {
    final enriched = await _enrich(context, question: userMessage);
    yield* inner.chat(enriched, history, userMessage);
  }

  Future<ReadingContext> _enrich(
    ReadingContext context, {
    String question = '',
    bool windowChapter = true,
  }) async {
    final guard = windowChapter && !context.allowSpoilers;
    final cutoff = context.pageStartOffset ?? context.chapterCharOffset;
    String guardedText() =>
        priorExcerpt(context.chapterText, endOffset: cutoff);

    if (context.bookId.isEmpty) {
      return guard
          ? context.copyWith(chapterText: guardedText())
          : context;
    }
    final digest = await source.load(context.bookId);
    if (digest == null || digest.isEmpty) {
      return guard
          ? context.copyWith(chapterText: guardedText())
          : context;
    }

    final assembled = assembler.assemble(
      AssembleInput(
        bookId: context.bookId,
        bookTitle: context.bookTitle,
        author: context.author,
        chapterIndex: context.chapterIndex,
        chapterTitle: context.chapterTitle,
        chapterText: context.chapterText,
        chapterCharOffset: context.chapterCharOffset,
        question: question,
        allowSpoilers: !guard,
      ),
      digest,
    );

    return context.copyWith(
      bookBrief: assembled.brief,
      chapterText: windowChapter
          ? (guard ? guardedText() : assembled.chapterExcerpt)
          : context.chapterText,
    );
  }
}
