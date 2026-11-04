import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/app.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/storage/book_storage.dart';
import 'package:coread/features/home/home_providers.dart';
import 'package:coread/features/home/section_rail.dart';

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mode_switch_test');
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
    await tester.tap(find.byKey(const Key('launcher-read')));
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the rail switch moves between 阅 and 搜 and back', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('rail-mode-search')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rail-mode-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-shell')).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-mode-read')));
    await tester.pumpAndSettle();
    expect(find.text('还没有书').hitTestable(), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a rail without a leading switch keeps the 阅 badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionRail(
            activeSection: AppSection.bookshelf,
            onSelectSection: (_) {},
            onSettings: () {},
          ),
        ),
      ),
    );

    expect(find.text('阅'), findsOneWidget);
    expect(find.byKey(const Key('mode-switch-search')), findsNothing);
  });
}
