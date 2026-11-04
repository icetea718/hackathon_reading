import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/chat_repository.dart';

void main() {
  late AppDatabase db;
  late ChatThreadRepository threads;
  late ChatMessageRepository messages;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    threads = ChatThreadRepository(db);
    messages = ChatMessageRepository(db);
  });

  tearDown(() => db.close());

  test('create returns a thread that shows up in watchAll', () async {
    final thread = await threads.create(title: '聊聊');

    final all = await threads.watchAll().first;
    expect(all.map((row) => row.id), [thread.id]);
    expect(all.single.title, '聊聊');
  });

  test('messages come back in the order they were appended', () async {
    final thread = await threads.create();

    await messages.append(threadId: thread.id, role: 'user', content: '你好');
    await messages.append(
      threadId: thread.id,
      role: 'assistant',
      content: '你好，有什么可以帮你？',
    );

    final list = await messages.list(thread.id);
    expect(list.map((row) => row.content), ['你好', '你好，有什么可以帮你？']);
    expect(list.first.status, 'complete');
  });

  test('deleting a thread removes its messages', () async {
    final thread = await threads.create();
    await messages.append(threadId: thread.id, role: 'user', content: 'hi');

    await threads.delete(thread.id);

    expect(await threads.watchAll().first, isEmpty);
    expect(await messages.list(thread.id), isEmpty);
  });

  test('touch lifts a thread to the top of watchAll', () async {
    final older = await threads.create(title: 'older');
    final newer = await threads.create(title: 'newer');
    expect(
      (await threads.watchAll().first).map((row) => row.id),
      [newer.id, older.id],
    );

    await threads.touch(older.id, title: 'renamed');

    final all = await threads.watchAll().first;
    expect(all.map((row) => row.id), [older.id, newer.id]);
    expect(all.first.title, 'renamed');
  });

  test('markStreamingAsInterrupted flips leftover rows', () async {
    final thread = await threads.create();
    final partial = await messages.append(
      threadId: thread.id,
      role: 'assistant',
      content: '半截',
      status: 'streaming',
    );
    final done = await messages.append(
      threadId: thread.id,
      role: 'assistant',
      content: '完整',
    );

    await messages.markStreamingAsInterrupted();

    final list = await messages.list(thread.id);
    expect(list.firstWhere((row) => row.id == partial.id).status, 'interrupted');
    expect(list.firstWhere((row) => row.id == done.id).status, 'complete');
  });

  test('updateContent rewrites the row and its status', () async {
    final thread = await threads.create();
    final row = await messages.append(
      threadId: thread.id,
      role: 'assistant',
      content: '',
      status: 'streaming',
    );

    await messages.updateContent(row.id, '写完了', status: 'interrupted');

    final updated = (await messages.list(thread.id)).single;
    expect(updated.content, '写完了');
    expect(updated.status, 'interrupted');
  });

  test('deriveTitle collapses newlines and truncates to 24 chars', () {
    expect(ChatThreadRepository.deriveTitle('  第一行\n第二行  '), '第一行 第二行');
    expect(ChatThreadRepository.deriveTitle('字' * 40).length, 24);
    expect(ChatThreadRepository.deriveTitle(''), '新对话');
  });
}
