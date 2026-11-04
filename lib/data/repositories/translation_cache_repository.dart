import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Remembers translations so the same passage is never translated twice.
abstract class TranslationCacheStore {
  Future<String?> find(String sourceText, {required String targetLang});

  Future<void> save(
    String sourceText, {
    required String targetLang,
    required String translatedText,
  });

  Future<void> remove(String sourceText, {required String targetLang});
}

class TranslationCacheRepository implements TranslationCacheStore {
  TranslationCacheRepository(this._db);

  final AppDatabase _db;

  @override
  Future<String?> find(String sourceText, {required String targetLang}) async {
    final hash = translationSourceHash(sourceText);
    final row = await (_db.select(_db.translationCaches)
          ..where(
            (t) => t.sourceHash.equals(hash) & t.targetLang.equals(targetLang),
          ))
        .getSingleOrNull();
    return row?.translatedText;
  }

  @override
  Future<void> save(
    String sourceText, {
    required String targetLang,
    required String translatedText,
  }) async {
    await _db.into(_db.translationCaches).insertOnConflictUpdate(
          TranslationCachesCompanion.insert(
            sourceHash: translationSourceHash(sourceText),
            targetLang: targetLang,
            translatedText: translatedText,
            createdAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> remove(String sourceText, {required String targetLang}) async {
    final hash = translationSourceHash(sourceText);
    await (_db.delete(_db.translationCaches)
          ..where(
            (t) => t.sourceHash.equals(hash) & t.targetLang.equals(targetLang),
          ))
        .go();
  }
}

/// Content addressed key: identical text always maps to the same entry.
String translationSourceHash(String text) =>
    sha256.convert(utf8.encode(text)).toString();
