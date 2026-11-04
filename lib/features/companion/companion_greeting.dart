import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../assistant/persona.dart';
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
    final persona = ref.read(personaModeProvider);
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
      _prompt(request, persona),
      persona: persona,
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

String _prompt(CompanionGreetingRequest request, PersonaMode persona) {
  final page = request.pageText.trim();
  final excerpt = page.length > 400 ? page.substring(0, 400) : page;
  return '你此刻的身份是「${persona.label}」：${persona.blurb}。\n'
      '他正在读《${request.bookTitle}》的「${request.chapterTitle}」，这一页写着：\n'
      '「$excerpt」\n'
      '${persona.greetingHint}\n'
      '就像你平时说话的口气，例如「${persona.sample}」。\n'
      '现在开口，直接给出你要对他说的那一句话：第一人称、口语，最多 25 个字，'
      '不用引号，不客套，不自我介绍，不复述原文。';
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
