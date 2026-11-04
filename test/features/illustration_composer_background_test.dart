import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';
import 'package:hackathon_reading/features/illustration/illustration_composer_page.dart';
import 'package:hackathon_reading/features/illustration/illustration_jobs.dart';
import 'package:hackathon_reading/illustration/illustration_config.dart';
import 'package:hackathon_reading/illustration/illustration_models.dart';
import 'package:hackathon_reading/illustration/illustration_service.dart';

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

class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const Key('open-composer'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const IllustrationComposerPage(
                  initialText: '雪夜的站台',
                  contextLabel: '测试 · 整章',
                ),
              ),
            ),
            child: const Text('打开生成页'),
          ),
          TextButton(
            key: const Key('reopen-job'),
            onPressed: () {
              final job = ref.read(illustrationJobProvider);
              if (job == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => IllustrationComposerPage(
                    jobId: job.id,
                    initialText: job.text,
                    contextLabel: job.label,
                  ),
                ),
              );
            },
            child: const Text('查看任务'),
          ),
        ],
      ),
    );
  }
}

Future<void> _pumpHost(
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
      ],
      child: const MaterialApp(home: _Host()),
    ),
  );
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byKey(const Key('open-composer'))),
  );
}

void main() {
  testWidgets('generation keeps going after leaving the composer',
      (tester) async {
    final completer = Completer<IllustrationResult>();
    await _pumpHost(tester, (onStage) {
      onStage?.call(IllustrationStage.planning);
      return completer.future;
    });

    await tester.tap(find.byKey(const Key('open-composer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始生成'));
    await tester.pump();

    expect(find.textContaining('正在分析文段'), findsOneWidget);
    expect(
      find.byKey(const Key('illustration-background')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('illustration-background')));
    await tester.pumpAndSettle();

    expect(find.byType(IllustrationComposerPage), findsNothing);
    expect(_container(tester).read(illustrationJobProvider)!.isRunning, isTrue);

    completer.complete(_result());
    await tester.pump();
    expect(
      _container(tester).read(illustrationJobProvider)!.status,
      IllustrationJobStatus.done,
    );
  });

  testWidgets('a running generation can be stopped from the composer',
      (tester) async {
    final completer = Completer<IllustrationResult>();
    await _pumpHost(tester, (onStage) => completer.future);

    await tester.tap(find.byKey(const Key('open-composer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始生成'));
    await tester.pump();

    expect(find.byKey(const Key('illustration-stop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('illustration-stop')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(IllustrationComposerPage)),
    );
    expect(container.read(illustrationJobProvider), isNull);
    expect(find.textContaining('正在分析文段'), findsNothing);
    expect(find.text('开始生成'), findsOneWidget);
  });

  testWidgets('reopening the job shows the finished illustration',
      (tester) async {
    await _pumpHost(tester, (onStage) async {
      onStage?.call(IllustrationStage.coloring);
      return _result();
    });

    _container(tester)
        .read(illustrationJobProvider.notifier)
        .start(text: '雪夜的站台', label: '测试 · 整章');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reopen-job')));
    await tester.pumpAndSettle();

    expect(find.byType(IllustrationComposerPage), findsOneWidget);
    expect(find.text('成品预览'), findsOneWidget);
    expect(find.text('保存到回忆录'), findsOneWidget);
  });
}
