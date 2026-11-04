import 'package:drift/drift.dart';

import 'converters.dart';

@DataClassName('BookRow')
@TableIndex(name: 'books_content_hash', columns: {#contentHash})
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get format => text()();
  TextColumn get sourcePath => text()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get contentHash => text().nullable()();
  BoolColumn get comic => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ChapterRecord')
@TableIndex(name: 'chapters_book_index', columns: {#bookId, #chapterIndex})
class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  IntColumn get chapterIndex => integer().named('chapter_index')();
  TextColumn get title => text()();
  IntColumn get startOffset => integer()();
  IntColumn get endOffset => integer()();
  TextColumn get contentText => text()();
  IntColumn get level => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AnnotationRecord')
@TableIndex(name: 'annotations_book_id', columns: {#bookId})
class Annotations extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get chapterId => text().nullable()();
  TextColumn get type => text()();
  IntColumn get anchorStart => integer()();
  IntColumn get anchorEnd => integer().nullable()();
  TextColumn get selectedText => text().withDefault(const Constant(''))();
  TextColumn get color => text().nullable()();
  TextColumn get noteText => text().withDefault(const Constant(''))();
  IntColumn get anchorVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SettingRecord')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ProgressRow')
class ReadingProgressEntries extends Table {
  TextColumn get bookId => text()();
  TextColumn get anchorJson => text()();
  RealColumn get percent => real()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

@DataClassName('DistillJobRow')
@TableIndex(name: 'distill_jobs_book', columns: {#bookId})
class DistillJobs extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get contentHash => text()();
  TextColumn get status => text()();
  TextColumn get stage => text()();
  IntColumn get pipelineVersion => integer()();
  IntColumn get totalUnits => integer().withDefault(const Constant(0))();
  IntColumn get doneUnits => integer().withDefault(const Constant(0))();
  TextColumn get errorText => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DistillUnitRow')
@TableIndex(name: 'distill_units_job_key', columns: {#jobId, #unitKey}, unique: true)
class DistillUnits extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text()();
  TextColumn get unitKey => text()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get resultJson => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRecord')
@TableIndex(name: 'categories_name', columns: {#name}, unique: true)
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BookCategoryRecord')
@TableIndex(name: 'book_categories_category', columns: {#categoryId})
class BookCategories extends Table {
  TextColumn get bookId => text()();
  TextColumn get categoryId => text()();

  @override
  Set<Column> get primaryKey => {bookId, categoryId};
}

@DataClassName('DistillArtifactRow')
@TableIndex(name: 'distill_artifacts_book_kind', columns: {#bookId, #kind})
class DistillArtifacts extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get kind => text()();
  TextColumn get unitKey => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get dataJson => text()();
  IntColumn get chapterStart => integer().nullable()();
  IntColumn get chapterEnd => integer().nullable()();
  BoolColumn get stale => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ChatThreadRow')
@TableIndex(name: 'chat_threads_updated', columns: {#updatedAt})
class ChatThreads extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get createdAt => text().map(const IsoDateTimeConverter())();
  TextColumn get updatedAt => text().map(const IsoDateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ChatMessageRow')
@TableIndex(name: 'chat_messages_thread', columns: {#threadId, #createdAt})
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get threadId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get sourcesJson => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('complete'))();
  TextColumn get createdAt => text().map(const IsoDateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}