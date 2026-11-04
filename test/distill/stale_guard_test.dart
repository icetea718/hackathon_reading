import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/distill_artifact_repository.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/distill.dart';
import 'package:coread/distill/stale_guard.dart';

String _hashOf(String text) => sha256.convert(utf8.encode(text)).toString();

void main() {
  late AppDatabase db;
  late Directory dir;
  late BookRepository books;
  late DistillArtifactRepository artifacts;
  late DistillStaleGuard guard;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('stale_guard');
    books = BookRepository(db);
    artifacts = DistillArtifactRepository(db);
    guard = DistillStaleGuard(books: books, artifacts: artifacts);
  });

  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> writeSource(String text) async {
    final file = File('${dir.path}/book.txt');
    await file.writeAsString(text);
    return file;
  }

  Future<void> seedBook(File file, {String? hash}) async {
    await books.upsert(Book(
      id: 'b1',
      title: '书',
      author: '',
      format: BookFormat.txt,
      sourcePath: file.path,
      addedAt: DateTime(2026, 1, 1),
      contentHash: hash,
    ));
    await artifacts.put(DistillArtifact(
      id: 'a1',
      bookId: 'b1',
      kind: DistillArtifactKind.overview,
      unitKey: 'overview',
      title: '总览',
      body: '正文',
      dataJson: '{}',
      stale: false,
      createdAt: DateTime(2026, 1, 2),
    ));
  }

  test('an unchanged file keeps artifacts fresh', () async {
    const text = '第一章的内容';
    final file = await writeSource(text);
    await seedBook(file, hash: _hashOf(text));

    final check = await guard.ensureFresh((await books.getById('b1'))!);

    expect(check.changed, isFalse);
    expect(check.hash, _hashOf(text));
    final stored = await artifacts.listByBook('b1');
    expect(stored.single.stale, isFalse);
  });

  test('a changed file marks artifacts stale and refreshes the hash', () async {
    final file = await writeSource('新的内容');
    await seedBook(file, hash: _hashOf('旧的内容'));

    final check = await guard.ensureFresh((await books.getById('b1'))!);

    expect(check.changed, isTrue);
    expect(check.hash, _hashOf('新的内容'));
    final stored = await artifacts.listByBook('b1');
    expect(stored.single.stale, isTrue);
    expect((await books.getById('b1'))!.contentHash, _hashOf('新的内容'));
  });

  test('a missing file is not treated as a change', () async {
    final file = File('${dir.path}/gone.txt');
    await seedBook(file, hash: 'whatever');

    final check = await guard.ensureFresh((await books.getById('b1'))!);

    expect(check.changed, isFalse);
    expect(check.hash, isNull);
    final stored = await artifacts.listByBook('b1');
    expect(stored.single.stale, isFalse);
  });
}
