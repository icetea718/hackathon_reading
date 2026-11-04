import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/app.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('launcher_page_test');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bookStorageProvider.overrideWith(
            (ref) async => BookStorage(Directory('${temp.path}/books')),
          ),
        ],
        child: const BookApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('cold start shows the launcher, not the bookshelf', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('今天想做什么？'), findsOneWidget);
    expect(find.byKey(const Key('launcher-search')), findsOneWidget);
    expect(find.byKey(const Key('launcher-read')), findsOneWidget);
    expect(find.text('还没有书'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('picking 阅 opens the bookshelf shell', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('launcher-read')));
    await tester.pumpAndSettle();

    expect(find.text('今天想做什么？'), findsNothing);
    expect(find.byTooltip('书架'), findsOneWidget);
    expect(find.text('还没有书'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('picking 搜 opens the chat shell', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('launcher-search')));
    await tester.pumpAndSettle();

    expect(find.text('今天想做什么？'), findsNothing);
    expect(find.byTooltip('书架'), findsNothing);
    expect(find.byKey(const Key('search-shell')), findsOneWidget);

    await disposeApp(tester);
  });
}
