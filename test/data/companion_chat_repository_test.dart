import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/companion_chat_repository.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';

void main() {
  late AppDatabase db;
  late CompanionChatRepository repo;
  late DateTime clock;
  var ids = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = DateTime(2026, 11, 4, 9);
    ids = 0;
    repo = CompanionChatRepository(
      db,
      newId: () => 'id-${ids++}',
      now: () => clock,
    );
  });

  tearDown(() => db.close());

  test('messages come back in sequence order', () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
    );

    await repo.appendMessage(
      threadId: thread.id,
      role: CompanionRole.user,
      content: 'q1',
    );
    await repo.appendMessage(
      threadId: thread.id,
      role: CompanionRole.assistant,
      content: 'a1',
    );
    await repo.appendMessage(
      threadId: thread.id,
      role: CompanionRole.user,
      content: 'q2',
    );

    final messages = await repo.messagesForThread(thread.id);
    expect(messages.map((m) => m.content), ['q1', 'a1', 'q2']);
    expect(messages.map((m) => m.seq), [1, 2, 3]);
  });

  test('latestThreadForChapter follows the most recently used thread',
      () async {
    final old = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 1,
      chapterTitle: '第二章',
      title: '旧',
    );
    await repo.createThread(
      bookId: 'b1',
      chapterIndex: 1,
      chapterTitle: '第二章',
      title: '新',
    );
    clock = clock.add(const Duration(minutes: 1));
    await repo.appendMessage(
      threadId: old.id,
      role: CompanionRole.user,
      content: '刚刚又问了一句',
    );

    final latest = await repo.latestThreadForChapter('b1', 1);
    expect(latest!.id, old.id);
  });

  test('threadsForBook counts messages per thread', () async {
    await repo.createThread(
      bookId: 'b1',
      chapterIndex: 1,
      chapterTitle: '第二章',
      title: 'A',
    );
    clock = clock.add(const Duration(minutes: 1));
    final b = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 1,
      chapterTitle: '第二章',
      title: 'B',
    );
    await repo.appendMessage(
      threadId: b.id,
      role: CompanionRole.user,
      content: 'q',
    );
    await repo.appendMessage(
      threadId: b.id,
      role: CompanionRole.assistant,
      content: 'a',
    );

    final rows = await repo.threadsForBook('b1');
    expect(rows.map((t) => t.messageCount), [2, 0]);
    expect(rows.first.title, 'B');
  });

  test('memory digest only includes chapters read before the current one',
      () async {
    final first = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: '一',
    );
    await repo.appendMessage(
      threadId: first.id,
      role: CompanionRole.user,
      content: '福贵是谁？',
    );
    await repo.appendMessage(
      threadId: first.id,
      role: CompanionRole.assistant,
      content: '地主家的少爷。',
    );
    final third = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 2,
      chapterTitle: '第三章',
      title: '三',
    );
    await repo.appendMessage(
      threadId: third.id,
      role: CompanionRole.user,
      content: '后面会怎样',
    );

    final digest = await repo.memoryDigest(bookId: 'b1', beforeChapterIndex: 2);
    expect(digest, contains('【第一章】'));
    expect(digest, contains('读者：'));
    expect(digest, contains('助手：'));
    expect(digest, isNot(contains('后面会怎样')));
  });

  test('memory digest keeps the newest three threads, oldest first', () async {
    for (final title in ['一', '二', '三', '四']) {
      final thread = await repo.createThread(
        bookId: 'b1',
        chapterIndex: 0,
        chapterTitle: title,
        title: title,
      );
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '问题$title',
      );
      clock = clock.add(const Duration(minutes: 1));
    }

    final digest = await repo.memoryDigest(bookId: 'b1', beforeChapterIndex: 1);
    expect(digest.length, lessThanOrEqualTo(400));
    expect(digest, isNot(contains('【一】')));
    expect(digest.indexOf('【二】') < digest.indexOf('【四】'), isTrue);
  });

  test('memory digest keeps only the last two messages per thread', () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: '一',
    );
    for (final content in ['第一问', '第一答', '第二问', '第二答']) {
      await repo.appendMessage(
        threadId: thread.id,
        role: content.endsWith('问')
            ? CompanionRole.user
            : CompanionRole.assistant,
        content: content,
      );
    }

    final digest = await repo.memoryDigest(bookId: 'b1', beforeChapterIndex: 1);
    expect(digest, contains('第二问'));
    expect(digest, contains('第二答'));
    expect(digest, isNot(contains('第一问')));
    expect(digest, isNot(contains('第一答')));
  });

  test('book memory digest defaults to the newest three threads', () async {
    final created = <CompanionThread>[];
    for (final title in ['一', '二', '三', '四']) {
      final thread = await repo.createThread(
        bookId: 'b1',
        chapterIndex: 0,
        chapterTitle: title,
        title: title,
      );
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '问题$title',
      );
      created.add(thread);
      clock = clock.add(const Duration(minutes: 1));
    }

    final digest = await repo.bookMemoryDigest(bookId: 'b1');

    expect(digest.text.length, lessThanOrEqualTo(1500));
    expect(digest.text, isNot(contains('【一】')));
    expect(digest.text, contains('【二】'));
    expect(digest.text, contains('【四】'));
    expect(
      digest.threadIds,
      {created[1].id, created[2].id, created[3].id},
    );
  });

  test('book memory digest keeps the whole conversation of a thread',
      () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: '一',
    );
    for (final content in ['第一问', '第一答', '第二问', '第二答']) {
      await repo.appendMessage(
        threadId: thread.id,
        role: content.endsWith('问')
            ? CompanionRole.user
            : CompanionRole.assistant,
        content: content,
      );
    }

    final digest = await repo.bookMemoryDigest(bookId: 'b1');

    for (final content in ['第一问', '第一答', '第二问', '第二答']) {
      expect(digest.text, contains(content));
    }
  });

  test('book memory digest keeps long messages whole', () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: '一',
    );
    await repo.appendMessage(
      threadId: thread.id,
      role: CompanionRole.assistant,
      content: '${'甲' * 300}结尾标记',
    );

    final digest = await repo.bookMemoryDigest(bookId: 'b1');

    expect(digest.text, contains('结尾标记'));
  });

  test('book memory digest drops whole messages when the budget runs out',
      () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: '一',
    );
    for (var i = 0; i < 4; i++) {
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '第$i条${'字' * 400}',
      );
    }

    final digest = await repo.bookMemoryDigest(bookId: 'b1');

    expect(digest.text.length, lessThanOrEqualTo(1500));
    expect(digest.text, contains('第3条${'字' * 400}'));
    expect(digest.text, isNot(contains('第0条')));
  });

  test('an explicit selection overrides the automatic threads', () async {
    final first = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: '一',
    );
    final second = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 1,
      chapterTitle: '第二章',
      title: '二',
    );
    clock = clock.add(const Duration(minutes: 1));
    final third = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 2,
      chapterTitle: '第三章',
      title: '三',
    );
    for (final thread in [first, second, third]) {
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '问题${thread.title}',
      );
    }

    final digest = await repo.bookMemoryDigest(
      bookId: 'b1',
      threadIds: {first.id, third.id},
    );

    expect(digest.text, contains('问题一'));
    expect(digest.text, contains('问题三'));
    expect(digest.text, isNot(contains('问题二')));
    expect(digest.threadIds, {first.id, third.id});
  });

  test('an empty selection means no companion context at all', () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
    );
    await repo.appendMessage(
      threadId: thread.id,
      role: CompanionRole.user,
      content: '问题',
    );

    final digest = await repo.bookMemoryDigest(
      bookId: 'b1',
      threadIds: const {},
    );

    expect(digest.text, isEmpty);
    expect(digest.threadIds, isEmpty);
  });

  test('a thread with no messages is not reported as included', () async {
    final empty = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '空',
    );

    final digest = await repo.bookMemoryDigest(bookId: 'b1');

    expect(digest.text, isEmpty);
    expect(digest.threadIds, isNot(contains(empty.id)));
  });

  test('a blank rename is ignored and a real one is trimmed', () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: '原标题',
    );

    await repo.renameThread(thread.id, '   ');
    expect((await repo.threadById(thread.id))!.title, '原标题');

    await repo.renameThread(thread.id, '  新标题  ');
    expect((await repo.threadById(thread.id))!.title, '新标题');
  });

  test('deleting a thread deletes its messages', () async {
    final thread = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
    );
    await repo.appendMessage(
      threadId: thread.id,
      role: CompanionRole.user,
      content: 'q',
    );

    await repo.deleteThread(thread.id);

    expect(await repo.threadById(thread.id), isNull);
    expect(await repo.messagesForThread(thread.id), isEmpty);
  });

  test('deleteForBook only removes that book', () async {
    final b1a = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: 'A',
    );
    final b1b = await repo.createThread(
      bookId: 'b1',
      chapterIndex: 1,
      chapterTitle: '第二章',
      title: 'B',
    );
    final b2 = await repo.createThread(
      bookId: 'b2',
      chapterIndex: 0,
      chapterTitle: '第一章',
      title: 'C',
    );
    for (final thread in [b1a, b1b, b2]) {
      await repo.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: 'q-${thread.id}',
      );
    }

    await repo.deleteForBook('b1');

    expect(await repo.threadsForBook('b1'), isEmpty);
    final other = await repo.threadsForBook('b2');
    expect(other, hasLength(1));
    expect(await repo.messagesForThread(b2.id), hasLength(1));
  });
}
