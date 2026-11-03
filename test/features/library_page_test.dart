import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/app.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/storage/book_storage.dart';
import 'package:hackathon_reading/domain/services/file_picker_service.dart';
import 'package:hackathon_reading/features/reader/reader_page.dart';

class FakeFilePicker implements FilePickerService {
  FakeFilePicker(this.path);

  final String? path;

  @override
  Future<String?> pickBookFile() async => path;
}

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('library_page_test');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> flushIo(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpApp(WidgetTester tester, String? pickedPath) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bookStorageProvider.overrideWith(
            (ref) async => BookStorage(Directory('${temp.path}/books')),
          ),
          filePickerProvider.overrideWithValue(FakeFilePicker(pickedPath)),
        ],
        child: const BookApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state initially', (tester) async {
    await pumpApp(tester, null);
    expect(find.text('还没有书，点右上角导入'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('importing a TXT adds a card with its title', (tester) async {
    final source = File('${temp.path}/我的 小说.TXT')
      ..writeAsStringSync('第一章 开始\n内容');
    await pumpApp(tester, source.path);

    await flushIo(tester, () => tester.tap(find.byTooltip('导入')));

    expect(find.text('我的 小说'), findsOneWidget);
    expect(Directory('${temp.path}/books').listSync(), hasLength(1));
    await disposeApp(tester);
  });

  testWidgets('tapping a TXT book opens the reader', (tester) async {
    final source = File('${temp.path}/novel.txt')
      ..writeAsStringSync('第一章 开始\n内容');
    await pumpApp(tester, source.path);

    await flushIo(tester, () => tester.tap(find.byTooltip('导入')));
    expect(find.text('novel'), findsOneWidget);

    await flushIo(tester, () => tester.tap(find.text('novel')));
    expect(find.byType(ReaderPage), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('back button returns from the reader to the library', (
    tester,
  ) async {
    final source = File('${temp.path}/novel.txt')
      ..writeAsStringSync('第一章 开始\n内容');
    await pumpApp(tester, source.path);

    await flushIo(tester, () => tester.tap(find.byTooltip('导入')));
    await flushIo(tester, () => tester.tap(find.text('novel')));
    expect(find.byType(ReaderPage), findsOneWidget);

    await flushIo(tester, () => tester.tap(find.byType(BackButton)));
    expect(find.byType(ReaderPage), findsNothing);
    expect(find.text('书架'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('delete removes the card and the copied file', (tester) async {
    final source = File('${temp.path}/t.txt')..writeAsStringSync('hello');
    await pumpApp(tester, source.path);

    await flushIo(tester, () => tester.tap(find.byTooltip('导入')));
    expect(find.text('t'), findsOneWidget);

    await flushIo(tester, () => tester.tap(find.byTooltip('删除')));
    await tester.pumpAndSettle();
    await flushIo(tester, () => tester.tap(find.widgetWithText(TextButton, '删除')));
    await tester.pumpAndSettle();

    expect(find.text('t'), findsNothing);
    expect(Directory('${temp.path}/books').listSync(), isEmpty);
    await disposeApp(tester);
  });

  testWidgets('unsupported file shows a friendly error message', (tester) async {
    final source = File('${temp.path}/a.doc')..writeAsStringSync('x');
    await pumpApp(tester, source.path);

    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('不支持的文件格式，请选择 EPUB、TXT 或 PDF'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('empty TXT shows a friendly error and leaves no book', (
    tester,
  ) async {
    final source = File('${temp.path}/empty.txt')..writeAsStringSync('');
    await pumpApp(tester, source.path);

    await flushIo(tester, () => tester.tap(find.byTooltip('导入')));

    expect(find.text('文件内容为空，无法导入'), findsOneWidget);
    expect(find.text('empty'), findsNothing);
    await disposeApp(tester);
  });
}
