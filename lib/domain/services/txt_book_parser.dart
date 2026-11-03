import '../models/detected_chapter.dart';
import 'txt_chapter_detector.dart';
import 'txt_decoder.dart';

class TxtDocument {
  const TxtDocument({
    required this.text,
    required this.encoding,
    required this.chapters,
  });

  final String text;
  final String encoding;
  final List<DetectedChapter> chapters;
}

TxtDocument parseTxtDocument(List<int> bytes, {required String fallbackTitle}) {
  final decoded = decodeTxtBytes(bytes);
  return TxtDocument(
    text: decoded.text,
    encoding: decoded.encoding,
    chapters: detectTxtChapters(decoded.text, fallbackTitle: fallbackTitle),
  );
}
