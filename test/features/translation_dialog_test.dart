import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/assistant/translation_exception.dart';
import 'package:coread/features/reader/translation_dialog.dart';

import '../support/fake_assistant_service.dart';
import '../support/fake_translation_cache.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  required String sourceText,
  required FakeAssistantService service,
  FakeTranslationCache? cache,
}) async {
  final store = cache ?? FakeTranslationCache();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => TranslationDialog(
                title: '翻译本章：第一章',
                sourceText: sourceText,
                service: service,
                cache: store,
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('streams the translation into the popup', (tester) async {
    final service = FakeAssistantService(chunks: ['你好，', '世界']);
    final cache = FakeTranslationCache();
    await _openDialog(
      tester,
      sourceText: 'Hello world',
      service: service,
      cache: cache,
    );

    expect(find.text('翻译本章：第一章'), findsOneWidget);
    expect(find.textContaining('目标语言：简体中文'), findsOneWidget);
    expect(find.text('你好，世界'), findsOneWidget);
    expect(service.translatedSources, ['Hello world']);
  });

  testWidgets('keeps the translated text wide instead of a one-column strip', (
    tester,
  ) async {
    final long =
        'The library smelled of old paper and dust. She turned the page '
        'slowly, afraid the story would end too soon.';
    await _openDialog(
      tester,
      sourceText: long,
      service: FakeAssistantService(chunks: const ['图书馆里是旧纸和灰尘的味道。']),
    );

    final textFinder = find.text('图书馆里是旧纸和灰尘的味道。');
    final box = tester.getSize(textFinder);
    // A squeezed layout wrapped the text into a ~30px column, so it grew tall.
    expect(box.width, greaterThan(200));
    expect(box.height, lessThan(80));
  });

  testWidgets('reuses the cached translation without calling the service', (
    tester,
  ) async {
    final service = FakeAssistantService(chunks: const ['新的译文']);
    final cache = FakeTranslationCache({'zh-CN|Hello world': '旧译文'});
    await _openDialog(
      tester,
      sourceText: 'Hello world',
      service: service,
      cache: cache,
    );

    expect(find.text('旧译文'), findsOneWidget);
    expect(find.textContaining('来自本地缓存'), findsOneWidget);
    expect(service.translatedSources, isEmpty);
    expect(find.text('重新翻译'), findsOneWidget);
  });

  testWidgets('重新翻译 drops the remembered text and asks again', (
    tester,
  ) async {
    final service = FakeAssistantService(chunks: const ['新译文']);
    final cache = FakeTranslationCache({'zh-CN|Hello world': '旧译文'});
    await _openDialog(
      tester,
      sourceText: 'Hello world',
      service: service,
      cache: cache,
    );

    await tester.tap(find.text('重新翻译'));
    await tester.pumpAndSettle();

    expect(cache.removals, 1);
    expect(cache.entries, isEmpty);
    expect(service.translatedSources, ['Hello world']);
    expect(find.text('新译文'), findsOneWidget);
  });

  testWidgets('shows a hint instead of translating Chinese text', (
    tester,
  ) async {
    final service = FakeAssistantService();
    await _openDialog(tester, sourceText: '这本来就已经是中文了。', service: service);

    expect(find.text('原文已是中文，无需翻译。'), findsOneWidget);
    expect(service.translatedSources, isEmpty);
  });

  testWidgets('does not cache a failed translation', (tester) async {
    final service = FakeAssistantService(
      error: const TranslationException('网络连接失败，请检查网络后重试'),
    );
    final cache = FakeTranslationCache();
    await _openDialog(
      tester,
      sourceText: 'Hello world',
      service: service,
      cache: cache,
    );

    expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(cache.entries, isEmpty);
  });

  testWidgets('closes from the close button', (tester) async {
    final service = FakeAssistantService(chunks: const ['译文']);
    await _openDialog(tester, sourceText: 'Hello', service: service);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationDialog), findsNothing);
  });
}
