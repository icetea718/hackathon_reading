import '../distill/llm/llm_client.dart';
import '../distill/llm/llm_config.dart';
import 'assistant_service.dart';
import 'reading_context.dart';

/// [AssistantService] backed by any OpenAI-compatible chat endpoint.
class OpenAiAssistantService implements AssistantService {
  OpenAiAssistantService({
    required this.client,
    required this.config,
  });

  final LlmClient client;
  final LlmConfig Function() config;

  @override
  bool get isConfigured => config().isConfigured;

  @override
  Stream<String> translate(String text, {required String targetLang}) {
    _ensureConfigured();
    return client.streamChat([
      _systemMessage(const ReadingContext(bookTitle: '')),
      LlmMessage(
        LlmRole.user,
        '把下面这段文字翻译成$targetLang，只输出译文：\n\n$text',
      ),
    ]);
  }

  @override
  Stream<String> explain(String text, {required ReadingContext context}) {
    _ensureConfigured();
    return client.streamChat([
      _systemMessage(context),
      LlmMessage(
        LlmRole.user,
        '结合这本书的语境，解释下面这段文字的意思，指出它在情节或情感上的作用：\n\n$text',
      ),
    ]);
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) {
    _ensureConfigured();
    return client.streamChat([
      _systemMessage(context),
      LlmMessage(
        LlmRole.user,
        '请总结「${context.chapterTitle}」这一章：先用一句话概括，再列出三到五个要点。'
        '不要剧透后面的章节。',
      ),
    ]);
  }

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage,
  ) {
    _ensureConfigured();
    return client.streamChat([
      _systemMessage(context),
      for (final message in history)
        LlmMessage(
          message.role == ChatRole.user ? LlmRole.user : LlmRole.assistant,
          message.content,
        ),
      LlmMessage(LlmRole.user, userMessage),
    ]);
  }

  void _ensureConfigured() {
    if (!isConfigured) throw const AssistantNotConfiguredException();
  }

  LlmMessage _systemMessage(ReadingContext context) {
    final lines = <String>[
      '你是阅读助手，陪读者一起读一本书，回答要具体、基于原文，不要编造情节。',
    ];
    if (context.bookTitle.isNotEmpty) {
      lines.add('书名：《${context.bookTitle}》');
    }
    if (context.author.isNotEmpty) {
      lines.add('作者：${context.author}');
    }
    if (context.chapterTitle.isNotEmpty) {
      lines.add('当前章节：${context.chapterTitle}');
    }
    final location = _pageLocation(context);
    if (location != null) {
      lines.add('读者当前位置：$location');
    }
    if (context.bookBrief.isNotEmpty) {
      lines.add('【全书蒸馏】\n${context.bookBrief}');
    }
    if (context.companionMemory.isNotEmpty) {
      lines.add('【此前章节的对话纪要】\n${context.companionMemory}');
    }
    if (context.currentPageText.isNotEmpty) {
      lines.add('【读者正在看的这一页】\n${context.currentPageText}');
    }
    if (context.chapterText.isNotEmpty) {
      lines.add('【当前章节内容】\n${context.chapterText}');
    }
    return LlmMessage(LlmRole.system, lines.join('\n'));
  }

  String? _pageLocation(ReadingContext context) {
    final page = context.chapterPage;
    if (page == null || page <= 0) return null;
    final count = context.chapterPageCount;
    final end = context.chapterPageEnd;
    final pages = end != null && end > page ? '第 $page–$end' : '第 $page';
    final chapter = count == null ? '$pages 页' : '$pages / $count 页';
    final book = context.bookPage;
    if (book == null) return chapter;
    final total = context.bookPageTotal;
    return '$chapter · 全书第 $book${total == null ? ' 页' : ' / $total 页'}';
  }
}
