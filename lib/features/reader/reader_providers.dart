import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/annotation.dart';
import '../../domain/models/book.dart';
import '../../domain/models/book_illustration.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/reading_progress.dart';

class ReaderData {
  const ReaderData({
    required this.book,
    required this.chapters,
    required this.progress,
    this.illustrations = const [],
  });

  final Book? book;
  final List<Chapter> chapters;
  final ReadingProgress? progress;
  final List<BookIllustration> illustrations;
}

final bookIllustrationsProvider = FutureProvider.autoDispose
    .family<List<BookIllustration>, String>((ref, bookId) async {
  final book = await ref.watch(bookRepositoryProvider).getById(bookId);
  if (book == null || book.format != BookFormat.epub || book.comic) {
    return const [];
  }
  final storage = await ref.watch(bookStorageProvider.future);
  final saved = await storage.loadIllustrations(bookId);
  if (saved != null) return saved;
  final service = await ref.watch(bookServiceProvider.future);
  await service.ensureIllustrations(book);
  return await storage.loadIllustrations(bookId) ?? const [];
});

final readerDataProvider =
    FutureProvider.autoDispose.family<ReaderData, String>((ref, bookId) async {
  final book = await ref.watch(bookRepositoryProvider).getById(bookId);
  final chapters =
      await ref.watch(chapterRepositoryProvider).getSummariesForBook(bookId);
  final progress = await ref.watch(progressRepositoryProvider).get(bookId);
  var illustrations = const <BookIllustration>[];
  if (book != null && book.format == BookFormat.epub && !book.comic) {
    try {
      illustrations = await ref.watch(bookIllustrationsProvider(bookId).future);
    } catch (_) {
      // Reading works without illustrations.
    }
  }
  return ReaderData(
    book: book,
    chapters: chapters,
    progress: progress,
    illustrations: illustrations,
  );
});

final bookmarkListProvider =
    FutureProvider.family<List<Annotation>, String>((ref, bookId) async {
  return ref
      .watch(annotationRepositoryProvider)
      .getForBook(bookId, type: AnnotationType.bookmark);
});

final readerAnnotationListProvider =
    FutureProvider.family<List<Annotation>, String>((ref, bookId) async {
  return ref.watch(annotationServiceProvider).getHighlightsAndNotes(bookId);
});

typedef ChapterContentKey = ({String bookId, int index});

final chapterContentProvider =
    FutureProvider.family<String, ChapterContentKey>((ref, key) async {
  final text = await ref
      .watch(chapterRepositoryProvider)
      .getContent(key.bookId, key.index);
  return text ?? '';
});
