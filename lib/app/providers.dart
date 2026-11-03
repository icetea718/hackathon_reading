import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../assistant/assistant_service.dart';
import '../assistant/unconfigured_assistant_service.dart';
import '../data/db/app_database.dart';
import '../data/repositories/annotation_repository.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/storage/book_storage.dart';
import '../distill/llm/llm_client.dart';
import '../distill/llm/llm_config.dart';
import '../distill/llm/openai_llm_client.dart';
import '../domain/models/book.dart';
import '../domain/services/annotation_service.dart';
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

final annotationServiceProvider = Provider<AnnotationService>((ref) {
  return AnnotationService(ref.watch(annotationRepositoryProvider));
});

final assistantServiceProvider = Provider<AssistantService>((ref) {
  return const UnconfiguredAssistantService();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

final llmConfigStoreProvider = Provider<LlmConfigStore>((ref) {
  return LlmConfigStore(ref.watch(settingsRepositoryProvider));
});

/// The stored LLM settings; invalidated whenever the settings page saves.
final llmConfigProvider = FutureProvider<LlmConfig>((ref) {
  return ref.watch(llmConfigStoreProvider).load();
});

/// Synchronous snapshot of [llmConfigProvider] for the client's config callback.
class LlmConfigSource {
  LlmConfig value = LlmConfig.defaults;
}

final llmConfigSourceProvider = Provider<LlmConfigSource>((ref) {
  final source = LlmConfigSource();
  ref.listen<AsyncValue<LlmConfig>>(
    llmConfigProvider,
    (previous, next) {
      if (next is AsyncData<LlmConfig>) source.value = next.value;
    },
    fireImmediately: true,
  );
  return source;
});

final llmClientProvider = Provider<LlmClient>((ref) {
  final source = ref.watch(llmConfigSourceProvider);
  final client = OpenAiLlmClient(config: () => source.value);
  ref.onDispose(client.dispose);
  return client;
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
