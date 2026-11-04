import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

/// Threads and messages of the 搜 (agent chat) shell.
///
/// Timestamps come from [DateTime.now] but are nudged forward when they would
/// not exceed the previous row, so ordering never depends on clock resolution.
class ChatThreadRepository {
  ChatThreadRepository(this._db);

  final AppDatabase _db;

  static const int titleLength = 24;
  static const String untitled = '新对话';

  /// Sidebar title: first line of the user's question, collapsed to one line.
  static String deriveTitle(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return untitled;
    return collapsed.length <= titleLength
        ? collapsed
        : collapsed.substring(0, titleLength);
  }

  Future<ChatThreadRow> create({String? title}) async {
    final id = const Uuid().v4();
    final latest = await _latestThreadUpdate();
    final now = _after(DateTime.now(), latest);
    await _db
        .into(_db.chatThreads)
        .insert(
          ChatThreadsCompanion.insert(
            id: id,
            title: Value((title ?? '').trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(_db.chatThreads)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Stream<List<ChatThreadRow>> watchAll() {
    final query = _db.select(_db.chatThreads)
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch();
  }

  Future<void> touch(String id, {String? title}) async {
    final trimmed = title?.trim();
    final latest = await _latestThreadUpdate();
    await (_db.update(_db.chatThreads)..where((row) => row.id.equals(id))).write(
      ChatThreadsCompanion(
        updatedAt: Value(_after(DateTime.now(), latest)),
        title: trimmed == null || trimmed.isEmpty
            ? const Value.absent()
            : Value(trimmed),
      ),
    );
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.chatMessages,
      )..where((row) => row.threadId.equals(id))).go();
      await (_db.delete(_db.chatThreads)..where((row) => row.id.equals(id))).go();
    });
  }

  Future<DateTime?> _latestThreadUpdate() async {
    final row = await (_db.select(_db.chatThreads)
          ..orderBy([(thread) => OrderingTerm.desc(thread.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.updatedAt;
  }

  DateTime _after(DateTime now, DateTime? previous) {
    if (previous == null || now.isAfter(previous)) return now;
    return previous.add(const Duration(milliseconds: 1));
  }
}

class ChatMessageRepository {
  ChatMessageRepository(this._db);

  final AppDatabase _db;

  Future<ChatMessageRow> append({
    required String threadId,
    required String role,
    required String content,
    String status = 'complete',
    String? sourcesJson,
  }) async {
    final id = const Uuid().v4();
    final now = _after(DateTime.now(), await _latestMessageTime(threadId));
    await _db
        .into(_db.chatMessages)
        .insert(
          ChatMessagesCompanion.insert(
            id: id,
            threadId: threadId,
            role: role,
            content: content,
            sourcesJson: Value(sourcesJson),
            status: Value(status),
            createdAt: now,
          ),
        );
    return (_db.select(_db.chatMessages)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<void> updateContent(
    String id,
    String content, {
    required String status,
    String? sourcesJson,
  }) {
    return (_db.update(_db.chatMessages)..where((row) => row.id.equals(id)))
        .write(
          ChatMessagesCompanion(
            content: Value(content),
            status: Value(status),
            sourcesJson: sourcesJson == null
                ? const Value.absent()
                : Value(sourcesJson),
          ),
        );
  }

  Future<List<ChatMessageRow>> list(String threadId) => _ordered(threadId).get();

  Stream<List<ChatMessageRow>> watch(String threadId) =>
      _ordered(threadId).watch();

  /// Called once at startup: a row still marked streaming belongs to a request
  /// that died with the previous process.
  Future<void> markStreamingAsInterrupted() {
    return (_db.update(_db.chatMessages)
          ..where((row) => row.status.equals('streaming')))
        .write(const ChatMessagesCompanion(status: Value('interrupted')));
  }

  SimpleSelectStatement<$ChatMessagesTable, ChatMessageRow> _ordered(
    String threadId,
  ) {
    return _db.select(_db.chatMessages)
      ..where((row) => row.threadId.equals(threadId))
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
  }

  Future<DateTime?> _latestMessageTime(String threadId) async {
    final row = await (_ordered(threadId)
          ..orderBy([(message) => OrderingTerm.desc(message.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.createdAt;
  }

  DateTime _after(DateTime now, DateTime? previous) {
    if (previous == null || now.isAfter(previous)) return now;
    return previous.add(const Duration(milliseconds: 1));
  }
}
