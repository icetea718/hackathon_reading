import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/app.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/features/settings/settings_page.dart';

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('home_shell_test');
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

  testWidgets('bookshelf is the default section and companion switches', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byTooltip('书架'), findsOneWidget);
    expect(find.byTooltip('陪读'), findsOneWidget);
    expect(find.text('还没有书'), findsOneWidget);

    await tester.tap(find.byTooltip('陪读'));
    await tester.pumpAndSettle();
    expect(find.text('陪读对话工作区即将上线'), findsOneWidget);

    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
    expect(find.text('还没有书'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('settings opens the existing settings page', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('the brand mark uses the larger serif style', (tester) async {
    await pumpApp(tester);

    final mark = tester.widget<Text>(find.text('阅'));
    expect(mark.style?.fontSize, 18);
    expect(mark.style?.fontWeight, FontWeight.w600);
    expect(mark.style?.fontFamily, 'Source Han Serif SC');

    final box = tester.widget<Container>(
      find.ancestor(of: find.text('阅'), matching: find.byType(Container)).first,
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(10));
    await disposeApp(tester);
  });

  testWidgets('the new-section entry is disabled', (tester) async {
    await pumpApp(tester);
    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('后续支持自定义分区'),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    await disposeApp(tester);
  });
}
