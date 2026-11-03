import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/assistant/assistant_service.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/assistant/unconfigured_assistant_service.dart';
import 'package:hackathon_reading/features/companion/companion_panel.dart';

class _FakeAssistant implements AssistantService {
  final List<String> prompts = [];

  @override
  bool get isConfigured => true;

  @override
  Stream<String> chat(
    ReadingContext context,
    List<ChatMessage> history,
    String userMessage,
  ) async* {
    prompts.add('chat:$userMessage');
    yield '福贵';
    yield '是因为赌博。';
  }

  @override
  Stream<String> summarizeChapter(ReadingContext context) async* {
    prompts.add('summary');
    yield '这一章讲福贵败家。';
  }

  @override
  Stream<String> explain(
    String text, {
    required ReadingContext context,
  }) async* {
    yield '解释';
  }

  @override
  Stream<String> translate(String text, {required String targetLang}) async* {
    yield '翻译';
  }
}

Widget _host(AssistantService service) => ProviderScope(
      overrides: [
        assistantServiceProvider.overrideWith((ref) async => service),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: CompanionPanel(
            bookId: 'book-1',
            chapterIndex: 1,
            chapterTitle: '第二章',
            chapterText: '福贵牵着老牛走在田埂上。',
            chapterCharOffset: 4,
          ),
        ),
      ),
    );

void main() {
  testWidgets('an unconfigured panel points at the settings page',
      (tester) async {
    await tester.pumpWidget(_host(const UnconfiguredAssistantService()));
    await tester.pumpAndSettle();

    expect(find.textContaining('未配置 AI 服务'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('sending a question streams the answer into the panel',
      (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '福贵为什么败家？');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(fake.prompts, contains('chat:福贵为什么败家？'));
    expect(find.text('福贵为什么败家？'), findsOneWidget);
    expect(find.textContaining('是因为赌博'), findsOneWidget);
  });

  testWidgets('the summary button streams a chapter summary', (tester) async {
    final fake = _FakeAssistant();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('总结本章'));
    await tester.pumpAndSettle();

    expect(fake.prompts, contains('summary'));
    expect(find.textContaining('福贵败家'), findsOneWidget);
  });
}
