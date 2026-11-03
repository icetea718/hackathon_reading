import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/app_database.dart';
import '../data/repositories/annotation_repository.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/storage/book_storage.dart';
import '../domain/models/book.dart';
import '../domain/services/book_service.dart';
import '../domain/services/file_picker_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.defaults();
  ref.onDispose(db.close);
  return db;
});

final bookRepositoryProvider = Provider<BookRepository>((ref) {
  return BookRepository(ref.watch(appDatabaseProvider));
});

final chapterRepositoryProvider = Provider<ChapterRepository>((ref) {
  return ChapterRepository(ref.watch(appDatabaseProvider));
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(ref.watch(appDatabaseProvider));
});

final annotationRepositoryProvider = Provider<AnnotationRepository>((ref) {
  return AnnotationRepository(ref.watch(appDatabaseProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

final bookStorageProvider = FutureProvider<BookStorage>((ref) async {
  final support = await getApplicationSupportDirectory();
  return BookStorage(Directory(p.join(support.path, 'books')));
});

final bookServiceProvider = FutureProvider<BookService>((ref) async {
  final service = BookService(
    books: ref.watch(bookRepositoryProvider),
    chapters: ref.watch(chapterRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    annotations: ref.watch(annotationRepositoryProvider),
    storage: await ref.watch(bookStorageProvider.future),
  );
  await service.backfillContentHashes();
  return service;
});

final filePickerProvider = Provider<FilePickerService>((ref) {
  return const SystemFilePicker();
});

final bookListProvider = StreamProvider<List<Book>>((ref) {
  return ref.watch(bookRepositoryProvider).watchAll();
});
