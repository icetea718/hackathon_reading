import 'package:drift/drift.dart';

import '../../domain/models/book.dart';
import '../db/app_database.dart';

class BookRepository {
  BookRepository(this._db);

  final AppDatabase _db;

  Stream<List<Book>> watchAll() {
    final query = _db.select(_db.books)
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]);
    return query.watch().map((rows) => rows.map(_toBook).toList());
  }

  Future<List<Book>> getAll() async {
    final query = _db.select(_db.books)
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]);
    final rows = await query.get();
    return rows.map(_toBook).toList();
  }

  Future<Book?> getById(String id) async {
    final query = _db.select(_db.books)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toBook(row);
  }

  Future<void> upsert(Book book) {
    return _db.into(_db.books).insertOnConflictUpdate(_toRow(book));
  }

  Future<void> delete(String id) {
    return (_db.delete(_db.books)..where((t) => t.id.equals(id))).go();
  }

  Book _toBook(BookRow row) {
    return Book(
      id: row.id,
      title: row.title,
      author: row.author,
      format: BookFormat.values.byName(row.format),
      sourcePath: row.sourcePath,
      coverPath: row.coverPath,
      addedAt: row.addedAt,
      lastOpenedAt: row.lastOpenedAt,
    );
  }

  BooksCompanion _toRow(Book book) {
    return BooksCompanion.insert(
      id: book.id,
      title: book.title,
      author: Value(book.author),
      format: book.format.name,
      sourcePath: book.sourcePath,
      coverPath: Value(book.coverPath),
      addedAt: book.addedAt,
      lastOpenedAt: Value(book.lastOpenedAt),
    );
  }
}
