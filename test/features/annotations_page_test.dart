import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/annotation_repository.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/chapter_repository.dart';
import 'package:coread/domain/models/annotation.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/features/annotations/annotations_page.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await BookRepository(db).upsert(Book(
      id: 'b1',
      title: '测试小说',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/b1.txt',
      addedAt: DateTime(2026, 1, 1),
    ));
    await ChapterRepository(db).replaceForBook('b1', [
      Chapter(
        id: 'c0',
        bookId: 'b1',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: 10,
        contentText: '0123456789',
      ),
      Chapter(
        id: 'c1',
        bookId: 'b1',
        index: 1,
        title: '第二章',
        startOffset: 10,
        endOffset: 20,
        contentText: 'abcdefghij',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedAnnotation({
    required String id,
    required AnnotationType type,
    required String chapterId,
    required int start,
    required int? end,
    String text = '',
    String? color = 'yellow',
    String note = '',
  }) async {
    await AnnotationRepository(db).upsert(Annotation(
      id: id,
      bookId: 'b1',
      chapterId: chapterId,
      type: type,
      anchorStart: start,
      anchorEnd: end,
      selectedText: text,
      color: color,
      noteText: note,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));
  }

  Future<List<Chapter>> chapters() => ChapterRepository(db).getSummariesForBook('b1');

  Future<void> pumpPage(
    WidgetTester tester, {
    required void Function(int? anchor) onResult,
  }) async {
    final chapterList = await chapters();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<int>(
                      MaterialPageRoute<int>(
                        builder: (_) => AnnotationsPage(
                          bookId: 'b1',
                          chapters: chapterList,
                        ),
                      ),
                    );
                    onResult(result);
                  },
                  child: const Text('打开标注'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开标注'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists highlights and notes with chapter titles', (tester) async {
    await seedAnnotation(
      id: 'h1',
      type: AnnotationType.highlight,
      chapterId: 'c0',
      start: 2,
      end: 5,
      text: '234',
      color: 'green',
    );
    await seedAnnotation(
      id: 'n1',
      type: AnnotationType.note,
      chapterId: 'c1',
      start: 12,
      end: 15,
      text: 'cde',
      color: null,
      note: '这里的伏笔',
    );
    await seedAnnotation(
      id: 'bm1',
      type: AnnotationType.bookmark,
      chapterId: 'c0',
      start: 1,
      end: null,
    );

    await pumpPage(tester, onResult: (_) {});

    expect(find.text('234'), findsOneWidget);
    expect(find.text('这里的伏笔'), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第二章'), findsOneWidget);
    expect(find.text('书签'), findsNothing);
  });

  testWidgets('shows an empty state without annotations', (tester) async {
    await pumpPage(tester, onResult: (_) {});

    expect(find.text('还没有高亮或笔记'), findsOneWidget);
  });

  testWidgets('tapping an annotation returns its anchor', (tester) async {
    await seedAnnotation(
      id: 'h1',
      type: AnnotationType.highlight,
      chapterId: 'c1',
      start: 12,
      end: 15,
      text: 'cde',
    );
    int? result;
    await pumpPage(tester, onResult: (anchor) => result = anchor);

    await tester.tap(find.text('cde'));
    await tester.pumpAndSettle();

    expect(result, 12);
    expect(find.byType(AnnotationsPage), findsNothing);
  });

  testWidgets('deleting an annotation removes it from the list', (tester) async {
    await seedAnnotation(
      id: 'h1',
      type: AnnotationType.highlight,
      chapterId: 'c0',
      start: 2,
      end: 5,
      text: '234',
    );
    await pumpPage(tester, onResult: (_) {});

    await tester.tap(find.byTooltip('删除标注'));
    await tester.pumpAndSettle();

    expect(find.text('234'), findsNothing);
    expect(find.text('还没有高亮或笔记'), findsOneWidget);
    expect(await AnnotationRepository(db).getForBook('b1'), isEmpty);
  });
}
