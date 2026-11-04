import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/book_repository.dart';
import 'package:hackathon_reading/data/repositories/chapter_repository.dart';
import 'package:hackathon_reading/data/repositories/progress_repository.dart';
import 'package:hackathon_reading/data/repositories/settings_repository.dart';
import 'package:hackathon_reading/domain/models/book.dart';
import 'package:hackathon_reading/domain/models/chapter.dart';
import 'package:hackathon_reading/features/reader/reader_page.dart';

void main() {
  late AppDatabase db;

  Future<void> seedLongBook() async {
    final buffer = StringBuffer();
    for (var i = 0; i < 60; i++) {
      buffer.writeln('第$i段：这是一段用来撑长页面的正文内容，确保可以滚动。');
    }
    final text = buffer.toString();
    await BookRepository(db).upsert(
      Book(
        id: 'long',
        title: '长书',
        author: '',
        format: BookFormat.txt,
        sourcePath: 'C:/books/long.txt',
        addedAt: DateTime(2026, 1, 3),
      ),
    );
    await ChapterRepository(db).replaceForBook('long', [
      Chapter(
        id: 'long-c0',
        bookId: 'long',
        index: 0,
        title: '第一章',
        startOffset: 0,
        endOffset: text.length,
        contentText: text,
      ),
    ]);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedLongBook();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpReader(WidgetTester tester, String bookId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: ReaderPage(bookId: bookId)),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> settleAfterIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<String?> storedRailPinned(WidgetTester tester) {
    return tester.runAsync<String?>(
      () => SettingsRepository(db).get('reader.railPinned'),
    );
  }

  ScrollController readerController(WidgetTester tester) {
    return tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
  }

  testWidgets('starts in immersive mode A', (tester) async {
    await pumpReader(tester, 'long');

    expect(find.byKey(const Key('reader-rail-pinned')), findsNothing);
    expect(find.byKey(const Key('reader-rail-overlay')), findsNothing);
    expect(find.byKey(const Key('reader-rail-hotzone')), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('the top bar pin button pins the rail and persists it', (
    tester,
  ) async {
    await pumpReader(tester, 'long');

    await tester.tap(find.byKey(const Key('reader-pin-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-rail-pinned')), findsOneWidget);
    await settleAfterIo(tester);
    expect(await storedRailPinned(tester), 'true');
    await disposeApp(tester);
  });

  testWidgets('a seeded pin restores mode B immediately', (tester) async {
    await SettingsRepository(db).set('reader.railPinned', 'true');
    await pumpReader(tester, 'long');

    expect(find.byKey(const Key('reader-rail-pinned')), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('the pin switch unpins and hides the rail', (tester) async {
    await SettingsRepository(db).set('reader.railPinned', 'true');
    await pumpReader(tester, 'long');
    expect(find.text('已固定'), findsOneWidget);

    await tester.tap(find.text('已固定'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('reader-rail-pinned')), findsNothing);
    expect(find.byKey(const Key('reader-rail-overlay')), findsNothing);
    await settleAfterIo(tester);
    expect(await storedRailPinned(tester), 'false');
    await disposeApp(tester);
  });

  testWidgets('hovering the edge shows the rail and leaving hides it', (
    tester,
  ) async {
    await pumpReader(tester, 'long');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(5, 300));
    addTearDown(gesture.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('reader-rail-overlay')), findsOneWidget);

    await gesture.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('reader-rail-overlay')), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('pinning keeps the reading position', (tester) async {
    await pumpReader(tester, 'long');
    final controller = readerController(tester);
    controller.jumpTo(controller.position.maxScrollExtent * 0.5);
    await tester.pump();
    final before = controller.offset / controller.position.maxScrollExtent;

    await tester.tap(find.byKey(const Key('reader-pin-button')));
    await tester.pumpAndSettle();

    final after = controller.offset / controller.position.maxScrollExtent;
    expect(after, closeTo(before, 0.02));
    await disposeApp(tester);
  });

  testWidgets('the rail bookshelf entry returns to the library', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReaderPage(bookId: 'long'),
                    ),
                  ),
                  child: const Text('打开阅读'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开阅读'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader-pin-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rail-bookshelf')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderPage), findsNothing);
    expect(find.text('打开阅读'), findsOneWidget);
  });

  testWidgets('unpinning keeps the reading position', (tester) async {
    await SettingsRepository(db).set('reader.railPinned', 'true');
    await pumpReader(tester, 'long');
    final controller = readerController(tester);
    controller.jumpTo(controller.position.maxScrollExtent * 0.5);
    await tester.pump();
    final before = controller.offset / controller.position.maxScrollExtent;

    await tester.tap(find.text('已固定'));
    await tester.pumpAndSettle();

    final after = controller.offset / controller.position.maxScrollExtent;
    expect(after, closeTo(before, 0.02));

    await disposeApp(tester);
    await settleAfterIo(tester);
    final progress = await tester.runAsync(
      () => ProgressRepository(db).get('long'),
    );
    expect(progress!.percent, closeTo(before, 0.05));
  });

  testWidgets('escape hides the floating rail', (tester) async {
    await pumpReader(tester, 'long');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(5, 300));
    addTearDown(gesture.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('reader-rail-overlay')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-rail-overlay')), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('a corrupt pin value stays safe in mode A', (tester) async {
    await SettingsRepository(db).set('reader.railPinned', 'banana');
    await pumpReader(tester, 'long');

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byKey(const Key('reader-rail-pinned')), findsNothing);
    expect(find.byKey(const Key('reader-rail-hotzone')), findsOneWidget);
    await disposeApp(tester);
  });
}
