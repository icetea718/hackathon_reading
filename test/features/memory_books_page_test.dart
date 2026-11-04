import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';
import 'package:hackathon_reading/features/illustration/illustration_composer_page.dart';
import 'package:hackathon_reading/features/illustration/illustration_jobs.dart';
import 'package:hackathon_reading/features/memory_book/memory_book_providers.dart';
import 'package:hackathon_reading/features/memory_book/memory_books_page.dart';
import 'package:hackathon_reading/illustration/illustration_config.dart';
import 'package:hackathon_reading/illustration/illustration_models.dart';
import 'package:hackathon_reading/illustration/illustration_service.dart';
import 'package:hackathon_reading/memory_book/memory_book_store.dart';

const _effective = IllustrationEffective(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'key',
  chatModel: 'chat',
  imageModel: 'image',
);

const _config = IllustrationConfig(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'key',
  chatModel: 'chat',
  imageModel: 'image',
);

const _llm = LlmConfig(
  baseUrl: 'https://api.example.com/v1',
  model: 'chat',
  apiKey: 'key',
);

IllustrationResult _result() => IllustrationResult(
      plan: const IllustrationPlan(
        medium: '水彩',
        sketchPrompt: 'sketch',
        colorPrompt: 'color',
      ),
      sketchFile: File('sketch.png'),
      finalFile: File('final.png'),
    );

class _FakeService extends IllustrationService {
  _FakeService(this._run) : super(effective: _effective);

  final Future<IllustrationResult> Function(
    void Function(IllustrationStage stage)? onStage,
  ) _run;

  @override
  Future<IllustrationResult> generate(
    String text, {
    void Function(IllustrationStage stage)? onStage,
  }) {
    return _run(onStage);
  }

  @override
  void dispose() {}
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memory_books_page_test');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold decoded image files.
    }
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Future<IllustrationResult> Function(
      void Function(IllustrationStage stage)? onStage,
    ) run,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          illustrationConfigProvider.overrideWith((ref) async => _config),
          llmConfigProvider.overrideWith((ref) async => _llm),
          illustrationServiceFactoryProvider.overrideWithValue(
            (_) => _FakeService(run),
          ),
          memoryBookStoreProvider.overrideWith((ref) async {
            final store = MemoryBookStore(temp);
            await store.init();
            return store;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MemoryBooksPage()),
        ),
      ),
    );
    // The empty-shelf state loads asynchronously; its loader never settles
    // with pumpAndSettle.
    await tester.pump();
    await tester.pump();
  }

  ProviderContainer container(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(MemoryBooksPage)),
    );
  }

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the running generation is visible above the books', (
    tester,
  ) async {
    final completer = Completer<IllustrationResult>();
    await pumpPage(tester, (onStage) {
      onStage?.call(IllustrationStage.planning);
      return completer.future;
    });

    container(tester).read(illustrationJobProvider.notifier).start(
          text: '雪夜的站台',
          label: '测试 · 整章',
        );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('memory-current-job')), findsOneWidget);
    expect(find.textContaining('插画生成中'), findsOneWidget);
    expect(find.text('查看进度'), findsOneWidget);

    await tester.tap(find.byKey(const Key('memory-current-job-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(IllustrationComposerPage), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('memory-current-job-stop')));
    await tester.pump();

    expect(find.byKey(const Key('memory-current-job')), findsNothing);
    expect(container(tester).read(illustrationJobProvider), isNull);
    await disposePage(tester);
  });

  testWidgets('a finished generation can be viewed from the books page', (
    tester,
  ) async {
    await pumpPage(tester, (onStage) async {
      onStage?.call(IllustrationStage.coloring);
      return _result();
    });

    container(tester).read(illustrationJobProvider.notifier).start(
          text: '雪夜的站台',
          label: '测试 · 整章',
        );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('插画已生成'), findsOneWidget);

    await tester.tap(find.byKey(const Key('memory-current-job-open')));
    await tester.pumpAndSettle();

    expect(find.byType(IllustrationComposerPage), findsOneWidget);
    expect(find.text('成品预览'), findsOneWidget);
    expect(find.text('保存到回忆录'), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('memory-current-job-dismiss')));
    await tester.pump();

    expect(find.byKey(const Key('memory-current-job')), findsNothing);
    await disposePage(tester);
  });
}
