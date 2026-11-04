import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/app.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/distill/llm/llm_config.dart';
import 'package:coread/features/illustration/illustration_composer_page.dart';
import 'package:coread/features/illustration/illustration_jobs.dart';
import 'package:coread/illustration/illustration_config.dart';
import 'package:coread/illustration/illustration_models.dart';
import 'package:coread/illustration/illustration_service.dart';

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
  testWidgets('a finished background job notifies from any page',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final completer = Completer<IllustrationResult>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          illustrationConfigProvider.overrideWith((ref) async => _config),
          llmConfigProvider.overrideWith((ref) async => _llm),
          illustrationServiceFactoryProvider.overrideWithValue(
            (_) => _FakeService((onStage) {
              onStage?.call(IllustrationStage.planning);
              return completer.future;
            }),
          ),
        ],
        child: const BookApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookApp)),
    );
    container.read(illustrationJobProvider.notifier).start(
          text: '雪夜的站台',
          label: '测试 · 整章',
        );
    await tester.pump();

    completer.complete(_result());
    await tester.pumpAndSettle();

    expect(find.text('插画已生成'), findsOneWidget);

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();

    expect(find.byType(IllustrationComposerPage), findsOneWidget);
    expect(find.text('成品预览'), findsOneWidget);
  });
}
