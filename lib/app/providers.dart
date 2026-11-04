import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../assistant/assistant_service.dart';
import '../assistant/cached_translation_service.dart';
import '../assistant/digest_aware_assistant_service.dart';
import '../assistant/my_memory_translator.dart';
import '../assistant/openai_assistant_service.dart';
import '../assistant/translation_router.dart';
import '../assistant/unconfigured_assistant_service.dart';
import '../data/db/app_database.dart';
import '../data/repositories/annotation_repository.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/distill_artifact_repository.dart';
import '../data/repositories/distill_job_repository.dart';
import '../data/repositories/distill_unit_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/translation_cache_repository.dart';
import '../data/storage/book_storage.dart';
import '../distill/distill_digest.dart';
import '../distill/llm/llm_client.dart';
import '../distill/llm/llm_config.dart';
import '../distill/llm/openai_llm_client.dart';
import '../domain/models/book.dart';
import '../domain/models/category.dart';
import '../domain/models/comic_page.dart';
import '../domain/models/distill.dart';
import '../domain/services/annotation_service.dart';
import '../domain/services/book_service.dart';
import '../domain/services/file_picker_service.dart';
import '../tts/audio_output.dart';
import '../tts/tts_client.dart';
import '../tts/tts_config.dart';
import '../tts/tts_service.dart';

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

final distillDigestSourceProvider = Provider<DistillDigestSource>((ref) {
  return RepositoryDistillDigestSource(
    ref.watch(distillArtifactRepositoryProvider),
  );
});

/// Assistant that always carries the book's distilled brief when one exists.
final assistantServiceProvider = FutureProvider<AssistantService>((ref) async {
  final config = await ref.watch(llmConfigStoreProvider).load();
  if (!config.isConfigured) return const UnconfiguredAssistantService();
  return DigestAwareAssistantService(
    inner: OpenAiAssistantService(
      client: ref.watch(llmClientProvider),
      config: () => ref.read(llmConfigSourceProvider).value,
    ),
    source: ref.watch(distillDigestSourceProvider),
  );
});

/// Free, key-less translation backend used when no model is configured.
final offlineTranslatorProvider = Provider<AssistantService>((ref) {
  return MyMemoryTranslator();
});

/// Remembers finished translations by source text, so a passage is only sent
/// to the model or the public API once.
final translationCacheProvider = Provider<TranslationCacheStore>((ref) {
  return TranslationCacheRepository(ref.watch(appDatabaseProvider));
});

/// Translation always works: the configured model when there is one, the free
/// public API otherwise. Finished results are remembered on disk.
final translationServiceProvider = Provider<AssistantService>((ref) {
  return CachedTranslationService(
    inner: TranslationRouter(
      preferred: ref.watch(assistantServiceProvider).value,
      fallback: ref.watch(offlineTranslatorProvider),
    ),
    cache: ref.watch(translationCacheProvider),
  );
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

/// Builds a short-lived client from an explicit config.
///
/// The settings page's "test connection" button needs the values currently in
/// the form, which are not in [llmConfigSourceProvider] yet: that snapshot only
/// refreshes once [llmConfigProvider] has reloaded from the database.
typedef LlmClientFactory = LlmClient Function(LlmConfig config);

final llmClientFactoryProvider = Provider<LlmClientFactory>((ref) {
  return (config) => OpenAiLlmClient(config: () => config);
});

final ttsConfigStoreProvider = Provider<TtsConfigStore>((ref) {
  return TtsConfigStore(ref.watch(settingsRepositoryProvider));
});

/// The stored voice settings; invalidated whenever the settings page saves.
final ttsConfigProvider = FutureProvider<TtsConfig>((ref) {
  return ref.watch(ttsConfigStoreProvider).load();
});

/// Synchronous snapshot of [ttsConfigProvider] for the client's callback.
class TtsConfigSource {
  TtsConfig value = TtsConfig.defaults;
}

final ttsConfigSourceProvider = Provider<TtsConfigSource>((ref) {
  final source = TtsConfigSource();
  ref.listen<AsyncValue<TtsConfig>>(
    ttsConfigProvider,
    (previous, next) {
      if (next is AsyncData<TtsConfig>) source.value = next.value;
    },
    fireImmediately: true,
  );
  return source;
});

final ttsClientProvider = Provider<TtsClient>((ref) {
  final source = ref.watch(ttsConfigSourceProvider);
  final client = OpenAiTtsClient(config: () => source.value);
  ref.onDispose(client.dispose);
  return client;
});

/// Builds a short-lived voice client from an explicit config.
///
/// Same reason as [llmClientFactoryProvider]: the "test voice" button must ping
/// the address that is on screen, not the snapshot that lags behind it.
typedef TtsClientFactory = TtsClient Function(TtsConfig config);

final ttsClientFactoryProvider = Provider<TtsClientFactory>((ref) {
  return (config) => OpenAiTtsClient(config: () => config);
});

final audioOutputProvider = Provider<AudioOutput>((ref) {
  final output = Platform.isWindows ? WinmmAudioOutput() : NoopAudioOutput();
  ref.onDispose(output.dispose);
  return output;
});

/// Speaks assistant replies; one instance serves every companion panel.
final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService(
    client: ref.watch(ttsClientProvider),
    output: ref.watch(audioOutputProvider),
    config: () => ref.read(ttsConfigSourceProvider).value,
    tempDirectory: () async {
      final base = await getTemporaryDirectory();
      final dir = Directory(p.join(base.path, 'tts'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

final distillJobRepositoryProvider = Provider<DistillJobRepository>((ref) {
  return DistillJobRepository(ref.watch(appDatabaseProvider));
});

final distillUnitRepositoryProvider = Provider<DistillUnitRepository>((ref) {
  return DistillUnitRepository(ref.watch(appDatabaseProvider));
});

final distillArtifactRepositoryProvider =
    Provider<DistillArtifactRepository>((ref) {
  return DistillArtifactRepository(ref.watch(appDatabaseProvider));
});

/// Artifacts written by a finished (or in-progress) distillation.
final distillArtifactsProvider =
    FutureProvider.family<List<DistillArtifact>, String>((ref, bookId) {
  return ref.watch(distillArtifactRepositoryProvider).listByBook(bookId);
});

final bookStorageProvider = FutureProvider<BookStorage>((ref) async {
  final support = await getApplicationSupportDirectory();
  return BookStorage(Directory(p.join(support.path, 'books')));
});

final comicPagesProvider =
    FutureProvider.family<List<ComicPage>, String>((ref, bookId) async {
  final storage = await ref.watch(bookStorageProvider.future);
  return storage.loadComicPages(bookId);
});

final bookServiceProvider = FutureProvider<BookService>((ref) async {
  final service = BookService(
    books: ref.watch(bookRepositoryProvider),
    chapters: ref.watch(chapterRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    annotations: ref.watch(annotationRepositoryProvider),
    storage: await ref.watch(bookStorageProvider.future),
    distillJobs: ref.watch(distillJobRepositoryProvider),
    distillUnits: ref.watch(distillUnitRepositoryProvider),
    distillArtifacts: ref.watch(distillArtifactRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
  );
  await service.backfillContentHashes();
  unawaited(service.backfillCovers());
  return service;
});

final filePickerProvider = Provider<FilePickerService>((ref) {
  return const SystemFilePicker();
});

final bookListProvider = StreamProvider<List<Book>>((ref) {
  return ref.watch(bookRepositoryProvider).watchAll();
});

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(appDatabaseProvider)),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);

final bookCategoryMembershipsProvider =
    StreamProvider<List<BookCategoryRecord>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchMemberships(),
);

final progressPercentsProvider = StreamProvider<Map<String, double>>(
  (ref) => ref.watch(progressRepositoryProvider).watchPercents(),
);
