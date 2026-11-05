import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/chat_repository.dart';

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

  test('watchForBook only returns the threads archived under that book', () async {
    final archived = await threads.create(title: '本书', bookId: 'b1');
    final loose = await threads.create(title: '未选书');

    expect(
      (await threads.watchForBook('b1').first).map((row) => row.id),
      [archived.id],
    );
    expect(
      (await threads.watchForBook(null).first).map((row) => row.id),
      [loose.id],
    );
    expect((await threads.watchAll().first).length, 2);
  });

  test('a blank bookId is stored as no book', () async {
    final thread = await threads.create(bookId: '   ');

    expect(thread.bookId, null);
    expect(
      (await threads.watchForBook(null).first).map((row) => row.id),
      [thread.id],
    );
  });

  test('latestForBook returns the most recently touched thread of that book',
      () async {
    final older = await threads.create(title: '旧', bookId: 'b1');
    final newer = await threads.create(title: '新', bookId: 'b1');
    await threads.create(title: '别的书', bookId: 'b2');

    expect((await threads.latestForBook('b1'))!.id, newer.id);

    await threads.touch(older.id);

    expect((await threads.latestForBook('b1'))!.id, older.id);
    expect((await threads.latestForBook(null)), null);
    expect((await threads.latestForBook('b9')), null);
  });

  test('deleteForBook removes the book threads and their messages', () async {
    final archived = await threads.create(bookId: 'b1');
    final other = await threads.create(bookId: 'b2');
    await messages.append(threadId: archived.id, role: 'user', content: 'hi');
    await messages.append(threadId: other.id, role: 'user', content: 'yo');

    await threads.deleteForBook('b1');

    expect(await threads.watchForBook('b1').first, isEmpty);
    expect(await messages.list(archived.id), isEmpty);
    expect((await threads.watchForBook('b2').first).single.id, other.id);
    expect((await messages.list(other.id)).single.content, 'yo');
  });

  test('append stores steps, updateSteps rewrites and clears them', () async {
    final thread = await threads.create();

    final withSteps = await messages.append(
      threadId: thread.id,
      role: 'assistant',
      content: '答案',
      stepsJson: '[{"tool":"search_in_book"}]',
    );
    expect(withSteps.stepsJson, '[{"tool":"search_in_book"}]');

    await messages.updateSteps(withSteps.id, '[{"tool":"get_chapter"}]');
    expect((await messages.list(thread.id)).single.stepsJson,
        '[{"tool":"get_chapter"}]');

    await messages.updateSteps(withSteps.id, null);
    expect((await messages.list(thread.id)).single.stepsJson, isNull);
    expect((await messages.list(thread.id)).single.content, '答案');
  });
}
