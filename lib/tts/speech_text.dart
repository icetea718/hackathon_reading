/// Turning assistant prose into something a TTS engine can pronounce.
///
/// Ported from the `speech-text.ts` module of
/// `@wocwang/cortico-world-gpt-sovits-for-coopanion`: stage directions such as
/// `【轻声】` or `<laugh>` and Markdown emphasis would otherwise be read out
/// loud, and emoji make GPT-SoVITS crash on an empty phoneme list.
library;

/// Bracketed runs longer than this are treated as prose, not as a tag.
const int inlineTagMax = 32;

/// Characters that end a spoken sentence.
const String _sentenceEnds = '。！？!?；;…';

/// Characters that may break a sentence that is too long for one request.
const String _softEnds = '，,、：:—–';

/// Chunk size handed to the synthesis endpoint.
///
/// Short enough that the first sentence is audible quickly, long enough that
/// prosody still has room to breathe.
const int defaultSpeechChunkChars = 60;

/// Strips stage directions and Markdown so the reply can be spoken.
String speechText(String script) {
  var text = script.replaceAll(RegExp(r'【[^】]*】'), ' ');
  text = text.replaceAllMapped(RegExp(r'[<＜]([^<>＜＞\n]*)[>＞]'), (match) {
    final inner = match[1] ?? '';
    return inner.length <= inlineTagMax ? ' ' : match[0]!;
  });
  text = text.replaceAll(RegExp(r'\*\*|__|`'), '');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Keeps letters, digits, punctuation and spaces; drops emoji and symbols.
///
/// GPT-SoVITS turns `♡★♪` into empty phonemes and then fails with
/// `torch.cat(): expected a non-empty list of Tensors`.
String ttsSafe(String text) {
  final stripped = text.replaceAll(
    RegExp(r'[^\p{L}\p{N}\p{P}\p{Zs}]', unicode: true),
    '',
  );
  return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Last-resort variant that keeps only letters, digits and spaces.
///
/// Used for the single retry when the engine rejects punctuation.
String ttsPlain(String text) {
  final stripped = text.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
    '',
  );
  return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Guesses the language of [text] from its script: `ja`, `ko`, `zh` or `en`.
String promptLanguageOf(String text) {
  var han = 0;
  var kana = 0;
  var hangul = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x3041 && rune <= 0x3096) ||
        (rune >= 0x30A1 && rune <= 0x30FA) ||
        rune == 0x30FC) {
      kana++;
    } else if ((rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F) ||
        (rune >= 0xAC00 && rune <= 0xD7AF)) {
      hangul++;
    } else if ((rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF)) {
      han++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A)) {
      latin++;
    }
  }
  if (kana > 0 && kana * 4 >= han) return 'ja';
  if (hangul > 0 && hangul >= han) return 'ko';
  if (han > 0 && han >= latin) return 'zh';
  if (latin > 0) return 'en';
  return 'zh';
}

/// Splits [text] into chunks small enough to synthesize one at a time.
///
/// Sentences end at [sentenceEnds]; a sentence longer than [maxChars] is broken
/// at commas, then hard-wrapped. Returns an empty list for blank input.
List<String> splitSpeech(
  String text, {
  int maxChars = defaultSpeechChunkChars,
}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  if (maxChars <= 0) return [normalized];

  final sentences = <String>[];
  final buffer = StringBuffer();
  void flush() {
    final sentence = buffer.toString().trim();
    if (sentence.isNotEmpty) sentences.add(sentence);
    buffer.clear();
  }

  for (final char in normalized.split('')) {
    buffer.write(char);
    if (_sentenceEnds.contains(char)) flush();
  }
  flush();

  final chunks = <String>[];
  for (final sentence in sentences) {
    chunks.addAll(_wrapLong(sentence, maxChars));
  }
  return chunks;
}

List<String> _wrapLong(String sentence, int maxChars) {
  if (sentence.length <= maxChars) return [sentence];
  final parts = <String>[];
  final buffer = StringBuffer();
  void flush() {
    final part = buffer.toString().trim();
    if (part.isNotEmpty) parts.add(part);
    buffer.clear();
  }

  for (final char in sentence.split('')) {
    buffer.write(char);
    final soft = _softEnds.contains(char);
    if (soft && buffer.length >= maxChars ~/ 2) {
      flush();
    } else if (buffer.length >= maxChars) {
      flush();
    }
  }
  flush();
  return parts;
}
