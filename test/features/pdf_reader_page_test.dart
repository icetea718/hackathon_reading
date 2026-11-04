import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/progress_repository.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/pdf_outline.dart';
import 'package:coread/domain/models/reading_progress.dart';
import 'package:coread/features/reader/pdf_reader_page.dart';
import 'package:coread/features/reader/pdf_reader_providers.dart';
import 'package:pdfrx/pdfrx.dart';

const _info = PdfBookInfo(
  pageCount: 5,
  outline: [
    PdfOutlineEntry(title: '第一章', pageNumber: 1, depth: 0),
    PdfOutlineEntry(title: '第二章', pageNumber: 4, depth: 0),
  ],
);

Widget _fakeViewer(
  BuildContext context, {
  required String path,
  required PdfViewerController controller,
  required int initialPageNumber,
  required ValueChanged<int?> onPageChanged,
  required void Function(PdfDocument document, PdfViewerController controller)
      onViewerReady,
}) {
  return const SizedBox.expand(key: Key('pdf-viewer'));
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await BookRepository(db).upsert(Book(
      id: 'pdf1',
      title: 'PDF 书',
      author: '',
      format: BookFormat.pdf,
      sourcePath: 'C:/books/pdf1.pdf',
      addedAt: DateTime(2026, 1, 1),
    ));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    PdfBookInfo info = _info,
    int? progressPage,
  }) async {
    if (progressPage != null) {
      await ProgressRepository(db).save(ReadingProgress(
        bookId: 'pdf1',
        anchor: ReadingAnchor.page(progressPage),
        percent: progressPage / info.pageCount,
        updatedAt: DateTime(2026, 1, 1),
      ));
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          pdfBookInfoProvider.overrideWith((ref, bookId) async => info),
          pdfViewerBuilderProvider.overrideWithValue(_fakeViewer),
        ],
        child: const MaterialApp(home: PdfReaderPage(bookId: 'pdf1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('restores the last page and renders the viewer', (tester) async {
    await pumpPage(tester, progressPage: 3);

    expect(find.byKey(const Key('pdf-viewer')), findsOneWidget);
    expect(find.text('3 / 5'), findsOneWidget);
  });

  testWidgets('next and previous buttons update the page indicator', (
    tester,
  ) async {
    await pumpPage(tester, progressPage: 2);

    await tester.tap(find.text('下一页'));
    await tester.pump();
    expect(find.text('3 / 5'), findsOneWidget);

    await tester.tap(find.text('上一页'));
    await tester.pump();
    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('jumps to a typed page number', (tester) async {
    await pumpPage(tester, progressPage: 2);

    await tester.tap(find.text('2 / 5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '4');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('4 / 5'), findsOneWidget);
  });

  testWidgets('rejects a page number outside the document', (tester) async {
    await pumpPage(tester, progressPage: 2);

    await tester.tap(find.text('2 / 5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('请输入 1 到 5 之间的页码'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('outline selection jumps to its page', (tester) async {
    await pumpPage(tester, progressPage: 1);

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    expect(find.text('第二章'), findsOneWidget);

    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();

    expect(find.text('4 / 5'), findsOneWidget);
  });

  testWidgets('falls back to a page list without an outline', (tester) async {
    await pumpPage(
      tester,
      info: const PdfBookInfo(pageCount: 5, outline: []),
      progressPage: 1,
    );

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    expect(find.text('这本书没有内嵌目录，可按页跳转'), findsOneWidget);

    await tester.tap(find.text('第 3 页'));
    await tester.pumpAndSettle();

    expect(find.text('3 / 5'), findsOneWidget);
  });

  testWidgets('adds and removes a bookmark for the current page', (
    tester,
  ) async {
    await pumpPage(tester, progressPage: 2);

    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    await tester.tap(find.byTooltip('书签'));
    await tester.pumpAndSettle();

    expect(find.text('已添加书签'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 页'), findsOneWidget);

    await tester.tap(find.byTooltip('删除书签'));
    await tester.pumpAndSettle();
    expect(find.text('还没有书签'), findsOneWidget);
  });

  testWidgets('tapping a bookmark jumps back to its page', (tester) async {
    await pumpPage(tester, progressPage: 2);

    await tester.tap(find.byTooltip('书签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一页'));
    await tester.pump();
    await tester.tap(find.text('下一页'));
    await tester.pump();
    expect(find.text('4 / 5'), findsOneWidget);

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 2 页'));
    await tester.pumpAndSettle();

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('saves the current page as progress', (tester) async {
    await pumpPage(tester, progressPage: 1);

    await tester.tap(find.text('下一页'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    final saved = await tester.runAsync(
      () => ProgressRepository(db).get('pdf1'),
    );
    expect(saved!.anchor.page, 2);
    expect(saved.percent, closeTo(2 / 5, 0.001));
  });
}
