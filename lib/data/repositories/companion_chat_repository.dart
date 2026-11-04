import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/companion_chat.dart';
import '../db/app_database.dart';

class CompanionChatRepository {
  CompanionChatRepository(
    this._db, {
    String Function()? newId,
    DateTime Function()? now,
  })  : _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? (() => DateTime.now());

  final AppDatabase _db;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<CompanionThread?> latestThreadForChapter(
    String bookId,
    int chapterIndex,
  ) async {
    final query = _db.select(_db.companionThreads)
      ..where(
        (t) => t.bookId.equals(bookId) & t.chapterIndex.equals(chapterIndex),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.updatedAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _toThread(row);
  }

  Future<CompanionThread?> threadById(String id) async {
    final query = _db.select(_db.companionThreads)
      ..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toThread(row);
  }

  Future<List<CompanionThread>> threadsForBook(String bookId) async {
    final query = _db.select(_db.companionThreads)
      ..where((t) => t.bookId.equals(bookId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.chapterIndex),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    final rows = await query.get();

    final countQuery = _db.selectOnly(_db.companionMessages)
      ..addColumns([
        _db.companionMessages.threadId,
        _db.companionMessages.id.count(),
      ])
      ..groupBy([_db.companionMessages.threadId]);
    final counts = <String, int>{};
    for (final row in await countQuery.get()) {
      final id = row.read(_db.companionMessages.threadId);
      if (id == null) continue;
      counts[id] = row.read(_db.companionMessages.id.count()) ?? 0;
    }

    return rows
        .map((row) => _toThread(row, messageCount: counts[row.id] ?? 0))
        .toList();
  }

  Future<CompanionThread> createThread({
    required String bookId,
    required int chapterIndex,
    required String chapterTitle,
    String title = '新对话',
  }) async {
    final time = _now();
    final row = CompanionThreadRecord(
      id: _newId(),
      bookId: bookId,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      title: title,
      createdAt: time,
      updatedAt: time,
    );
    await _db.into(_db.companionThreads).insert(row);
    return _toThread(row);
  }

  Future<void> renameThread(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await (_db.update(_db.companionThreads)..where((t) => t.id.equals(id)))
        .write(CompanionThreadsCompanion(title: Value(trimmed)));
  }

  Future<void> deleteThread(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.companionMessages)
            ..where((m) => m.threadId.equals(id)))
          .go();
      await (_db.delete(_db.companionThreads)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  Future<List<CompanionMessage>> messagesForThread(String threadId) async {
    final query = _db.select(_db.companionMessages)
      ..where((m) => m.threadId.equals(threadId))
      ..orderBy([(m) => OrderingTerm.asc(m.seq)]);
    final rows = await query.get();
    return rows.map(_toMessage).toList();
  }

  Future<CompanionMessage> appendMessage({
    required String threadId,
    required CompanionRole role,
    required String content,
  }) {
    return _db.transaction(() async {
      final maxQuery = _db.selectOnly(_db.companionMessages)
        ..addColumns([_db.companionMessages.seq.max()])
        ..where(_db.companionMessages.threadId.equals(threadId));
      final maxSeq =
          (await maxQuery.getSingle()).read(_db.companionMessages.seq.max()) ??
              0;

      final time = _now();
      final row = CompanionMessageRecord(
        id: _newId(),
        threadId: threadId,
        role: role.name,
        content: content,
        seq: maxSeq + 1,
        createdAt: time,
      );
      await _db.into(_db.companionMessages).insert(row);
      await (_db.update(_db.companionThreads)
            ..where((t) => t.id.equals(threadId)))
          .write(CompanionThreadsCompanion(updatedAt: Value(time)));
      return _toMessage(row);
    });
  }

  Future<String> memoryDigest({
    required String bookId,
    required int beforeChapterIndex,
    int maxChars = 400,
  }) async {
    if (maxChars <= 0) return '';
    final threadQuery = _db.select(_db.companionThreads)
      ..where(
        (t) =>
            t.bookId.equals(bookId) &
            t.chapterIndex.isSmallerThanValue(beforeChapterIndex),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.updatedAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ])
      ..limit(3);
    final threads = await threadQuery.get();

    final segments = <String>[];
    var used = 0;
    for (final thread in threads) {
      final messageQuery = _db.select(_db.companionMessages)
        ..where((m) => m.threadId.equals(thread.id))
        ..orderBy([(m) => OrderingTerm.desc(m.seq)])
        ..limit(2);
      final messages = (await messageQuery.get()).reversed.toList();
      if (messages.isEmpty) continue;

      final body = messages.map((message) {
        final label = CompanionRole.fromName(message.role) ==
                CompanionRole.user
            ? '读者'
            : '助手';
        return '$label：${_clip(message.content)}';
      }).join(' ');
      final segment = '【${thread.chapterTitle}】$body';
      final nextUsed = used + segment.length + (segments.isEmpty ? 0 : 1);
      if (nextUsed > maxChars) break;
      segments.add(segment);
      used = nextUsed;
    }
    return segments.reversed.join('\n');
  }

  Future<void> deleteForBook(String bookId) async {
    final query = _db.selectOnly(_db.companionThreads)
      ..addColumns([_db.companionThreads.id])
      ..where(_db.companionThreads.bookId.equals(bookId));
    final ids = (await query.get())
        .map((row) => row.read(_db.companionThreads.id))
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return;

    await _db.transaction(() async {
      await (_db.delete(_db.companionMessages)
            ..where((m) => m.threadId.isIn(ids)))
          .go();
      await (_db.delete(_db.companionThreads)..where((t) => t.id.isIn(ids)))
          .go();
    });
  }

  CompanionThread _toThread(
    CompanionThreadRecord row, {
    int messageCount = 0,
  }) {
    return CompanionThread(
      id: row.id,
      bookId: row.bookId,
      chapterIndex: row.chapterIndex,
      chapterTitle: row.chapterTitle,
      title: row.title,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      messageCount: messageCount,
    );
  }

  CompanionMessage _toMessage(CompanionMessageRecord row) {
    return CompanionMessage(
      id: row.id,
      threadId: row.threadId,
      role: CompanionRole.fromName(row.role),
      content: row.content,
      seq: row.seq,
      createdAt: row.createdAt,
    );
  }

  String _clip(String text) {
    return text.length <= 100 ? text : '${text.substring(0, 100)}…';
  }
}
