/// Parsed shapes of the JSON the distillation prompts ask for.
class DistillParseException implements Exception {
  DistillParseException(this.message, {this.raw});

  final String message;
  final String? raw;

  @override
  String toString() => 'DistillParseException: $message';
}

class MapResult {
  const MapResult({
    this.points = const [],
    this.entities = const [],
    this.toneCues = const [],
    this.quotes = const [],
  });

  final List<String> points;
  final List<String> entities;
  final List<String> toneCues;
  final List<String> quotes;
}

class ChapterGist {
  const ChapterGist({
    required this.chapterIndex,
    required this.title,
    required this.gist,
  });

  final int chapterIndex;
  final String title;
  final String gist;
}

class PartResult {
  const PartResult({required this.summary, this.chapters = const []});

  final String summary;
  final List<ChapterGist> chapters;
}

class ThemeArc {
  const ThemeArc({
    required this.title,
    required this.chapters,
    this.note = '',
  });

  final String title;
  final List<int> chapters;
  final String note;
}

class BookOverview {
  const BookOverview({
    required this.oneLiner,
    required this.synopsis,
    this.themes = const [],
    this.structure = const [],
    this.argument = '',
  });

  final String oneLiner;
  final String synopsis;
  final List<String> themes;
  final List<ThemeArc> structure;
  final String argument;
}

class ToneArc {
  const ToneArc({required this.chapterIndex, required this.tone});

  final int chapterIndex;
  final String tone;
}

class ToneProfile {
  const ToneProfile({
    required this.overall,
    this.narrator = '',
    this.arc = const [],
    this.style = const [],
    this.sampleQuotes = const [],
  });

  final String overall;
  final String narrator;
  final List<ToneArc> arc;
  final List<String> style;
  final List<String> sampleQuotes;
}

class DistillCard {
  const DistillCard({
    required this.slug,
    required this.title,
    required this.type,
    required this.definition,
    this.sourceChapters = const [],
    this.quote,
  });

  final String slug;
  final String title;
  final String type;
  final String definition;
  final List<int> sourceChapters;
  final String? quote;
}
