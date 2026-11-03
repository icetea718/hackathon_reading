import 'dart:convert';

import '../data/repositories/distill_artifact_repository.dart';
import '../domain/models/distill.dart';

/// One distilled key point of the book.
class DistillDigestCard {
  const DistillDigestCard({
    required this.slug,
    required this.title,
    required this.definition,
    this.sourceChapters = const [],
    this.quote,
  });

  final String slug;
  final String title;
  final String definition;
  final List<int> sourceChapters;
  final String? quote;
}

/// Compact, prompt-ready view of everything distillation learned about a book.
class DistillDigest {
  const DistillDigest({
    this.oneLiner = '',
    this.synopsis = '',
    this.themes = const [],
    this.toneOverall = '',
    this.toneStyle = const [],
    this.gists = const {},
    this.cards = const [],
  });

  final String oneLiner;
  final String synopsis;
  final List<String> themes;
  final String toneOverall;
  final List<String> toneStyle;

  /// chapterIndex -> one sentence gist.
  final Map<int, String> gists;
  final List<DistillDigestCard> cards;

  bool get isEmpty =>
      oneLiner.isEmpty &&
      synopsis.isEmpty &&
      themes.isEmpty &&
      toneOverall.isEmpty &&
      gists.isEmpty &&
      cards.isEmpty;
}

/// Loads the digest for a book; `null` means the book was never distilled.
abstract class DistillDigestSource {
  Future<DistillDigest?> load(String bookId);
}

/// Builds a [DistillDigest] from the artifacts written by the pipeline.
class RepositoryDistillDigestSource implements DistillDigestSource {
  RepositoryDistillDigestSource(this._artifacts);

  final DistillArtifactRepository _artifacts;

  @override
  Future<DistillDigest?> load(String bookId) async {
    final artifacts = await _artifacts.listByBook(bookId);
    if (artifacts.isEmpty) return null;

    var oneLiner = '';
    var synopsis = '';
    var themes = <String>[];
    var toneOverall = '';
    var toneStyle = <String>[];
    final gists = <int, String>{};
    final cards = <DistillDigestCard>[];

    for (final artifact in artifacts) {
      final data = _decode(artifact.dataJson);
      switch (artifact.kind) {
        case DistillArtifactKind.overview:
          oneLiner = _string(data['oneLiner']);
          synopsis = _string(data['synopsis']);
          themes = _strings(data['themes']);
        case DistillArtifactKind.tone:
          toneOverall = _string(data['overall']);
          toneStyle = _strings(data['style']);
        case DistillArtifactKind.chapterGist:
          final index = artifact.chapterStart;
          if (index != null) {
            gists[index] = _string(data['gist']).isEmpty
                ? artifact.body
                : _string(data['gist']);
          }
        case DistillArtifactKind.card:
          cards.add(
            DistillDigestCard(
              slug: _string(data['slug']).isEmpty
                  ? artifact.unitKey
                  : _string(data['slug']),
              title: artifact.title,
              definition: artifact.body,
              sourceChapters: _ints(data['sourceChapters']),
              quote: _string(data['quote']).isEmpty
                  ? null
                  : _string(data['quote']),
            ),
          );
      }
    }

    return DistillDigest(
      oneLiner: oneLiner,
      synopsis: synopsis,
      themes: themes,
      toneOverall: toneOverall,
      toneStyle: toneStyle,
      gists: gists,
      cards: cards,
    );
  }

  static Map<String, Object?> _decode(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map<String, Object?> ? value : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _string(Object? value) => value is String ? value : '';

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList()
      : const <String>[];

  static List<int> _ints(Object? value) => value is List
      ? value.whereType<num>().map((n) => n.toInt()).toList()
      : const <int>[];
}
