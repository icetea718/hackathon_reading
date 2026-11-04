import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/assistant/translation_exception.dart';
import 'package:hackathon_reading/features/reader/translation_dialog.dart';

import '../support/fake_assistant_service.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  required String sourceText,
  required FakeAssistantService service,
}) async {
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
    await _openDialog(tester, sourceText: 'Hello world', service: service);

    expect(find.text('翻译本章：第一章'), findsOneWidget);
    expect(find.text('目标语言：简体中文'), findsOneWidget);
    expect(find.text('你好，\n世界'), findsOneWidget);
    expect(service.translatedSources, ['Hello world']);
  });

  testWidgets('shows a hint instead of translating Chinese text', (
    tester,
  ) async {
    final service = FakeAssistantService();
    await _openDialog(tester, sourceText: '这本来就已经是中文了。', service: service);

    expect(find.text('原文已是中文，无需翻译。'), findsOneWidget);
    expect(service.translatedSources, isEmpty);
  });

  testWidgets('shows the failure message from the service', (tester) async {
    final service = FakeAssistantService(
      error: const TranslationException('网络连接失败，请检查网络后重试'),
    );
    await _openDialog(tester, sourceText: 'Hello world', service: service);

    expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('shows the not-configured hint for AI-only services', (
    tester,
  ) async {
    final service = FakeAssistantService(error: Exception('boom'));
    await _openDialog(tester, sourceText: 'Hello', service: service);

    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('closes from the close button', (tester) async {
    final service = FakeAssistantService(chunks: const ['译文']);
    await _openDialog(tester, sourceText: 'Hello', service: service);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationDialog), findsNothing);
  });
}
