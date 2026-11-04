import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/annotation_repository.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/companion_chat_repository.dart';
import 'package:hackathon_reading/domain/models/annotation.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';
import 'package:hackathon_reading/features/search/book_memory_sheet.dart';
import 'package:hackathon_reading/search/companion_selection.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  final time = DateTime(2026, 11, 4);

  Book shelfBook() {
    return Book(
      id: 'b1',
      title: '活着',
      author: '余华',
      format: BookFormat.epub,
      sourcePath: '/books/huozhe.epub',
      addedAt: time,
    );
  }

  Future<void> seed(WidgetTester tester, {bool withMaterial = true}) async {
    await tester.runAsync(() async {
      await BookRepository(db).upsert(shelfBook());
      if (!withMaterial) return;

      final annotations = AnnotationRepository(db);
      await annotations.upsert(
        Annotation(
          id: 'a1',
          bookId: 'b1',
          type: AnnotationType.bookmark,
          anchorStart: 0,
          selectedText: '书签段落',
          createdAt: time,
          updatedAt: time,
        ),
      );
      await annotations.upsert(
        Annotation(
          id: 'a2',
          bookId: 'b1',
          type: AnnotationType.highlight,
          anchorStart: 0,
          selectedText: '划线句子',
          createdAt: time,
          updatedAt: time,
        ),
      );
      await annotations.upsert(
        Annotation(
          id: 'a3',
          bookId: 'b1',
          type: AnnotationType.note,
          anchorStart: 0,
          noteText: '我的笔记',
          createdAt: time,
          updatedAt: time,
        ),
      );

      final chats = CompanionChatRepository(db);
      final first = await chats.createThread(
        bookId: 'b1',
        chapterIndex: 0,
        chapterTitle: '第一章',
        title: '福贵是谁',
      );
      await chats.appendMessage(
        threadId: first.id,
        role: CompanionRole.user,
        content: '福贵是谁？',
      );
      await chats.appendMessage(
        threadId: first.id,
        role: CompanionRole.assistant,
        content: '地主家的少爷。',
      );
      final second = await chats.createThread(
        bookId: 'b1',
        chapterIndex: 1,
        chapterTitle: '第二章',
        title: '后面的故事',
      );
      await chats.appendMessage(
        threadId: second.id,
        role: CompanionRole.user,
        content: '后面会怎样？',
      );
    });
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: BookMemorySheet(bookId: 'b1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('the four tabs show the reader material', (tester) async {
    await seed(tester);
    await pumpSheet(tester);

    expect(find.byKey(const Key('book-memory-sheet')), findsOneWidget);
    expect(find.text('书签段落'), findsOneWidget);

    await openTab(tester, '高亮');
    expect(find.text('「划线句子」'), findsOneWidget);

    await openTab(tester, '笔记');
    expect(find.text('我的笔记'), findsOneWidget);

    await openTab(tester, '陪读对话');
    expect(find.text('福贵是谁'), findsOneWidget);
    expect(find.text('后面的故事'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('companion threads start checked and the choice is remembered',
      (tester) async {
    await seed(tester);
    await pumpSheet(tester);
    await openTab(tester, '陪读对话');

    final checks = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .map((box) => box.value)
        .toList();
    expect(checks, everyElement(isTrue));

    final threadId = (await tester.runAsync(
      () async {
        final rows = await CompanionChatRepository(db).threadsForBook('b1');
        return rows.last.id;
      },
    ))!;
    await tester.tap(find.byKey(Key('companion-check-$threadId')));
    await tester.pumpAndSettle();

    expect(
      container.read(companionSelectionProvider('b1')),
      isNot(contains(threadId)),
    );

    await tester.tap(find.byKey(const Key('companion-reset')));
    await tester.pumpAndSettle();
    expect(container.read(companionSelectionProvider('b1')), null);
    await unmount(tester);
  });

  testWidgets('expanding a companion thread shows its messages',
      (tester) async {
    final threadId = await tester.runAsync(() async {
      await BookRepository(db).upsert(shelfBook());
      final chats = CompanionChatRepository(db);
      final thread = await chats.createThread(
        bookId: 'b1',
        chapterIndex: 0,
        chapterTitle: '第一章',
        title: '福贵是谁',
      );
      await chats.appendMessage(
        threadId: thread.id,
        role: CompanionRole.user,
        content: '福贵是谁？',
      );
      await chats.appendMessage(
        threadId: thread.id,
        role: CompanionRole.assistant,
        content: '地主家的少爷。',
      );
      return thread.id;
    });

    await pumpSheet(tester);
    await openTab(tester, '陪读对话');
    await tester.tap(find.byKey(Key('companion-thread-$threadId')));
    await tester.pumpAndSettle();

    expect(find.textContaining('福贵是谁？'), findsOneWidget);
    expect(find.textContaining('地主家的少爷。'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('empty material shows quiet empty states', (tester) async {
    await seed(tester, withMaterial: false);
    await pumpSheet(tester);

    expect(find.text('还没有书签'), findsOneWidget);
    await openTab(tester, '高亮');
    expect(find.text('还没有高亮'), findsOneWidget);
    await openTab(tester, '笔记');
    expect(find.text('还没有笔记'), findsOneWidget);
    await openTab(tester, '陪读对话');
    expect(find.text('还没有陪读对话'), findsOneWidget);
    await unmount(tester);
  });
}
