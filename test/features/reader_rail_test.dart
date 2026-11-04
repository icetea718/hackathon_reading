import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/chapter_repository.dart';
import 'package:coread/data/repositories/settings_repository.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/features/reader/reader_page.dart';

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

  String pageText(WidgetTester tester) {
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    final buffer = StringBuffer();
    void write(InlineSpan span) {
      if (span is! TextSpan) return;
      buffer.write(span.text ?? '');
      for (final child in span.children ?? const <InlineSpan>[]) {
        write(child);
      }
    }

    write(selectable.textSpan!);
    return buffer.toString();
  }

  Future<void> tapNextZone(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('reader-next-zone')));
    await tester.pumpAndSettle();
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

  testWidgets('the pin switch unpins into the floating rail', (tester) async {
    await SettingsRepository(db).set('reader.railPinned', 'true');
    await pumpReader(tester, 'long');
    expect(find.text('已固定'), findsOneWidget);

    await tester.tap(find.text('已固定'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('reader-rail-pinned')), findsNothing);
    expect(find.byKey(const Key('reader-rail-overlay')), findsOneWidget);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));
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
    await tapNextZone(tester);
    await tapNextZone(tester);
    final anchorText = pageText(tester).substring(0, 10);

    await tester.tap(find.byKey(const Key('reader-pin-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-rail-pinned')), findsOneWidget);
    expect(pageText(tester), contains(anchorText));
    await disposeApp(tester);
  });

  testWidgets('unpinning from the rail keeps it until the mouse leaves', (
    tester,
  ) async {
    await SettingsRepository(db).set('reader.railPinned', 'true');
    await pumpReader(tester, 'long');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('已固定')));
    addTearDown(gesture.removePointer);
    await tester.pump();

    await tester.tap(find.text('已固定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('reader-rail-overlay')), findsOneWidget);

    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('reader-rail-overlay'))),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(const Offset(500, 300));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('reader-rail-overlay')), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('the floating rail casts a shadow', (tester) async {
    await pumpReader(tester, 'long');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(5, 300));
    addTearDown(gesture.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final containers = tester.widgetList<Container>(
      find.descendant(
        of: find.byKey(const Key('reader-rail-overlay')),
        matching: find.byType(Container),
      ),
    );
    expect(
      containers.any((container) {
        final decoration = container.decoration;
        return decoration is BoxDecoration &&
            (decoration.boxShadow?.isNotEmpty ?? false);
      }),
      isTrue,
    );
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
    await tapNextZone(tester);
    await tapNextZone(tester);
    final anchorText = pageText(tester).substring(0, 10);

    await tester.tap(find.text('已固定'));
    await tester.pumpAndSettle();

    expect(pageText(tester), contains(anchorText));

    await disposeApp(tester);
    await settleAfterIo(tester);
    await pumpReader(tester, 'long');
    expect(pageText(tester), contains(anchorText));
    await disposeApp(tester);
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
