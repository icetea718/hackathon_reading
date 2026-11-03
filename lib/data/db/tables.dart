import 'package:drift/drift.dart';

@DataClassName('BookRow')
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get format => text()();
  TextColumn get sourcePath => text()();
  TextColumn get coverPath => text().nullable()();
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

@DataClassName('ProgressRow')
class ReadingProgressEntries extends Table {
  TextColumn get bookId => text()();
  TextColumn get anchorJson => text()();
  RealColumn get percent => real()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}
