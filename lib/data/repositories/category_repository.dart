import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/category.dart';
import '../db/app_database.dart';

class InvalidCategoryNameException implements Exception {
  InvalidCategoryNameException(this.name);

  final String name;

  @override
  String toString() => 'InvalidCategoryNameException: $name';
}

class DuplicateCategoryException implements Exception {
  DuplicateCategoryException(this.name);

  final String name;

  @override
  String toString() => 'DuplicateCategoryException: $name';
}

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  Stream<List<Category>> watchAll() {
    final query = _db.select(_db.categories)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  Future<List<Category>> getAll() async {
    final query = _db.select(_db.categories)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  Future<Category> create(String name) async {
    final trimmed = _validate(name);
    if (await _findByName(trimmed) != null) {
      throw DuplicateCategoryException(trimmed);
    }

    final maxSort = _db.categories.sortOrder.max();
    final max = await (_db.selectOnly(
      _db.categories,
    )..addColumns([maxSort])).map((row) => row.read(maxSort)).getSingleOrNull();
    final sortOrder = (max ?? -1) + 1;
    final createdAt = DateTime.now();

    final id = const Uuid().v4();
    await _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            name: trimmed,
            sortOrder: Value(sortOrder),
            createdAt: createdAt,
          ),
        );
    return Category(
      id: id,
      name: trimmed,
      sortOrder: sortOrder,
      createdAt: createdAt,
    );
  }

  Future<void> rename(String id, String name) async {
    final trimmed = _validate(name);
    final existing = await _findByName(trimmed);
    if (existing != null && existing.id != id) {
      throw DuplicateCategoryException(trimmed);
    }
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(name: Value(trimmed)),
    );
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.bookCategories,
      )..where((t) => t.categoryId.equals(id))).go();
      await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
    });
  }

  Stream<List<BookCategoryRecord>> watchMemberships() {
    return _db.select(_db.bookCategories).watch();
  }

  Future<void> setBookCategories(String bookId, Set<String> categoryIds) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.bookCategories,
      )..where((t) => t.bookId.equals(bookId))).go();
      for (final categoryId in categoryIds) {
        await _db
            .into(_db.bookCategories)
            .insert(
              BookCategoriesCompanion.insert(
                bookId: bookId,
                categoryId: categoryId,
              ),
            );
      }
    });
  }

  Future<void> addBook(String bookId, String categoryId) async {
    await _db
        .into(_db.bookCategories)
        .insert(
          BookCategoriesCompanion.insert(
            bookId: bookId,
            categoryId: categoryId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> removeBook(String bookId, String categoryId) async {
    await (_db.delete(_db.bookCategories)..where(
          (t) => t.bookId.equals(bookId) & t.categoryId.equals(categoryId),
        ))
        .go();
  }

  Future<void> removeCategoryFromBooks(
    String categoryId,
    Set<String> bookIds,
  ) async {
    if (bookIds.isEmpty) return;
    await (_db.delete(_db.bookCategories)..where(
          (t) =>
              t.categoryId.equals(categoryId) & t.bookId.isIn(bookIds.toList()),
        ))
        .go();
  }

  Future<void> deleteForBook(String bookId) async {
    await (_db.delete(
      _db.bookCategories,
    )..where((t) => t.bookId.equals(bookId))).go();
  }

  Future<CategoryRecord?> _findByName(String name) {
    final query = _db.select(_db.categories)..where((t) => t.name.equals(name));
    return query.getSingleOrNull();
  }

  String _validate(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 20) {
      throw InvalidCategoryNameException(name);
    }
    return trimmed;
  }

  Category _toModel(CategoryRecord row) {
    return Category(
      id: row.id,
      name: row.name,
      sortOrder: row.sortOrder,
      createdAt: row.createdAt,
    );
  }
}
