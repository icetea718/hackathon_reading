import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/reading_progress.dart';

class ReaderData {
  const ReaderData({
    required this.book,
    required this.chapters,
    required this.progress,
  });

  final Book? book;
  final List<Chapter> chapters;
  final ReadingProgress? progress;
}

final readerDataProvider =
    FutureProvider.family<ReaderData, String>((ref, bookId) async {
  final book = await ref.watch(bookRepositoryProvider).getById(bookId);
  final chapters =
      await ref.watch(chapterRepositoryProvider).getForBook(bookId);
  final progress = await ref.watch(progressRepositoryProvider).get(bookId);
  return ReaderData(book: book, chapters: chapters, progress: progress);
});
