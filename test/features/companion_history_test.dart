import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/domain/models/companion_chat.dart';
import 'package:hackathon_reading/features/companion/companion_history.dart';

CompanionThread _thread({
  required String id,
  required int chapterIndex,
  required String chapterTitle,
  required String title,
  int messageCount = 0,
}) {
  final time = DateTime(2026, 11, 4, 10);
  return CompanionThread(
    id: id,
    bookId: 'b1',
    chapterIndex: chapterIndex,
    chapterTitle: chapterTitle,
    title: title,
    createdAt: time,
    updatedAt: time,
    messageCount: messageCount,
  );
}

Widget _host(
  List<CompanionThread> threads, {
  int currentChapterIndex = 0,
  bool loading = false,
  ValueChanged<CompanionThread>? onOpen,
  void Function(CompanionThread thread, String title)? onRename,
  ValueChanged<CompanionThread>? onDelete,
  VoidCallback? onNewThread,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CompanionHistoryView(
        threads: threads,
        currentChapterIndex: currentChapterIndex,
        loading: loading,
        onNewThread: onNewThread ?? () {},
        onOpen: onOpen ?? (_) {},
        onRename: onRename ?? (_, _) {},
        onDelete: onDelete ?? (_) {},
      ),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('companion-thread-menu-$id')));
  await tester.pumpAndSettle();
}

void main() {
  test('recent times fall back from minutes to dates', () {
    final now = DateTime(2026, 11, 4, 15, 30);
    expect(
      formatCompanionTime(
        now.subtract(const Duration(seconds: 20)),
        now: now,
      ),
      '刚刚',
    );
    expect(
      formatCompanionTime(now.subtract(const Duration(minutes: 5)), now: now),
      '5 分钟前',
    );
    expect(
      formatCompanionTime(DateTime(2026, 11, 4, 9, 5), now: now),
      '今天 09:05',
    );
    expect(
      formatCompanionTime(DateTime(2026, 11, 3, 22, 0), now: now),
      '昨天 22:00',
    );
    expect(
      formatCompanionTime(DateTime(2026, 10, 1, 8, 0), now: now),
      '10月1日',
    );
    expect(
      formatCompanionTime(DateTime(2025, 10, 1, 8, 0), now: now),
      '2025年10月1日',
    );
  });

  testWidgets('the current chapter is listed first and marked', (tester) async {
    final threads = [
      _thread(
        id: 'old',
        chapterIndex: 0,
        chapterTitle: '第一章',
        title: '旧章节对话',
      ),
      _thread(
        id: 'now',
        chapterIndex: 2,
        chapterTitle: '第三章',
        title: '当前对话',
      ),
    ];
    await tester.pumpWidget(_host(threads, currentChapterIndex: 2));

    expect(find.text('当前章'), findsOneWidget);
    expect(find.text('只读'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('当前对话')).dy,
      lessThan(tester.getTopLeft(find.text('旧章节对话')).dy),
    );
  });

  testWidgets('rename saves the trimmed title and cancel keeps the old one',
      (tester) async {
    String? saved;
    var renameCount = 0;
    final threads = [
      _thread(
        id: 't1',
        chapterIndex: 0,
        chapterTitle: '第一章',
        title: '原标题',
        messageCount: 2,
      ),
    ];
    await tester.pumpWidget(
      _host(
        threads,
        onRename: (_, title) {
          saved = title;
          renameCount++;
        },
      ),
    );

    expect(find.textContaining('共 2 条'), findsOneWidget);

    await _openMenu(tester, 't1');
    await tester.tap(find.byKey(const Key('companion-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('companion-rename-field')),
      '  新名字  ',
    );
    await tester.tap(find.byKey(const Key('companion-rename-save')));
    await tester.pumpAndSettle();

    expect(saved, '新名字');
    expect(renameCount, 1);

    await _openMenu(tester, 't1');
    await tester.tap(find.byKey(const Key('companion-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('companion-rename-field')),
      '不要保存',
    );
    await tester.tap(find.byKey(const Key('companion-rename-cancel')));
    await tester.pumpAndSettle();

    expect(renameCount, 1);
  });

  testWidgets('delete asks the panel to remove the thread', (tester) async {
    CompanionThread? deleted;
    final threads = [
      _thread(
        id: 't1',
        chapterIndex: 0,
        chapterTitle: '第一章',
        title: '对话',
      ),
    ];
    await tester.pumpWidget(_host(threads, onDelete: (thread) {
      deleted = thread;
    }));

    await _openMenu(tester, 't1');
    await tester.tap(find.byKey(const Key('companion-menu-delete')));
    await tester.pumpAndSettle();

    expect(deleted!.id, 't1');
  });
}
