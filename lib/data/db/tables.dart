import 'package:drift/drift.dart';

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
