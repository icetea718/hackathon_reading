import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../assistant/reading_context.dart';

/// What the reader is looking at when the companion picks a line to say.
class CompanionGreetingRequest {
  const CompanionGreetingRequest({
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.chapterText,
    required this.pageText,
    required this.readerOffset,
    this.bookTitle = '',
    this.author = '',
  });

  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final String chapterText;
  final String pageText;
  final int readerOffset;
  final String bookTitle;
  final String author;
}

/// Produces one short line for the speech bubble, or null when the companion
/// has nothing to say (offline, unconfigured, provider error).
typedef CompanionGreeter = Future<String?> Function(
  CompanionGreetingRequest request,
);

/// Bounds on the line the companion may say, in characters.
const companionGreetingMaxLength = 48;

final companionGreeterProvider = Provider<CompanionGreeter>(
  (ref) => (request) => _greetWithAssistant(ref, request),
);

Future<String?> _greetWithAssistant(
  Ref ref,
  CompanionGreetingRequest request,
) async {
  try {
    final service = await ref.read(assistantServiceProvider.future);
    if (!service.isConfigured) return null;
    final stream = service.chat(
      ReadingContext(
        bookTitle: request.bookTitle,
        author: request.author,
        chapterTitle: request.chapterTitle,
        chapterText: request.chapterText,
        bookId: request.bookId,
        chapterIndex: request.chapterIndex,
        chapterCharOffset: request.readerOffset,
      ),
      const [],
      _prompt(request),
    );
    final buffer = StringBuffer();
    await for (final chunk in stream) {
      buffer.write(chunk);
      if (buffer.length > companionGreetingMaxLength * 2) break;
      if (_endsSentence(buffer.toString())) break;
    }
    return condenseGreeting(buffer.toString());
  } catch (_) {
    return null;
  }
}

bool _endsSentence(String text) {
  final trimmed = text.trimRight();
  if (trimmed.isEmpty) return false;
  return '。！？!?'.contains(trimmed[trimmed.length - 1]);
}

String _prompt(CompanionGreetingRequest request) {
  final page = request.pageText.trim();
  final excerpt = page.length > 400 ? page.substring(0, 400) : page;
  return '你是一个坐在读者身边的陪读伙伴，说话轻松、口语化。'
      '他正在读《${request.bookTitle}》的「${request.chapterTitle}」，这一页写着：\n'
      '「$excerpt」\n'
      '请对他说一句搭话，要求：不超过 25 个字；可以提一句这一页正在发生的事；'
      '不要用引号，不要客套，不要提问开场，直接给出这句话本身。';
}

/// Trims a raw model answer down to one clean bubble line.
///
/// Returns null when nothing usable is left.
String? condenseGreeting(String raw) {
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  text = text.replaceFirst(RegExp(r'^(陪读|伙伴|助手)[:：]\s*'), '');
  text = text.replaceFirst(RegExp('^["“”\'‘’「『]+'), '');
  text = text.replaceFirst(RegExp('["“”\'‘’」』]+\$'), '');
  final stop = text.indexOf(RegExp('[。！？!?]'));
  if (stop >= 0) {
    text = text.substring(0, stop + 1);
  }
  text = text.trim();
  if (text.isEmpty) return null;
  if (text.length > companionGreetingMaxLength) {
    text = '${text.substring(0, companionGreetingMaxLength).trimRight()}…';
  }
  return text;
}
