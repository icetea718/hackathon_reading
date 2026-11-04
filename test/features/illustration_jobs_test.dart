import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/providers.dart';
import 'package:coread/distill/llm/llm_config.dart';
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

ProviderContainer _container(
  Future<IllustrationResult> Function(
    void Function(IllustrationStage stage)? onStage,
  ) run,
) {
  return ProviderContainer(
    overrides: [
      illustrationConfigProvider.overrideWith((ref) async => _config),
      llmConfigProvider.overrideWith((ref) async => _llm),
      illustrationServiceFactoryProvider.overrideWithValue(
        (_) => _FakeService(run),
      ),
    ],
  );
}

void main() {
  test('a job reports its stage and result', () async {
    final completer = Completer<IllustrationResult>();
    final container = _container((onStage) {
      onStage?.call(IllustrationStage.planning);
      return completer.future;
    });
    addTearDown(container.dispose);
    final notifier = container.read(illustrationJobProvider.notifier);

    final id = notifier.start(text: ' 一段文字 ', label: '测试 · 选中文字');
    await Future<void>.delayed(Duration.zero);

    final running = container.read(illustrationJobProvider)!;
    expect(running.status, IllustrationJobStatus.running);
    expect(running.stage, IllustrationStage.planning);
    expect(running.text, '一段文字');
    expect(running.label, '测试 · 选中文字');

    completer.complete(_result());
    await Future<void>.delayed(Duration.zero);

    expect(id, running.id);
    final done = container.read(illustrationJobProvider)!;
    expect(done.status, IllustrationJobStatus.done);
    expect(done.result?.finalFile.path, 'final.png');
    expect(done.error, isNull);
  });

  test('a second job is refused while one is still running', () async {
    final completer = Completer<IllustrationResult>();
    final container = _container((onStage) => completer.future);
    addTearDown(container.dispose);
    final notifier = container.read(illustrationJobProvider.notifier);

    notifier.start(text: '第一段', label: '第一段');
    await Future<void>.delayed(Duration.zero);
    final second = notifier.start(text: '第二段', label: '第二段');

    expect(second, isNull);
    expect(container.read(illustrationJobProvider)!.text, '第一段');

    completer.complete(_result());
    await Future<void>.delayed(Duration.zero);
  });

  test('a failed generation keeps the error and can be replaced', () async {
    var calls = 0;
    final container = _container((onStage) async {
      calls++;
      if (calls == 1) throw IllustrationException('接口挂了');
      return _result();
    });
    addTearDown(container.dispose);
    final notifier = container.read(illustrationJobProvider.notifier);

    notifier.start(text: '一段文字', label: '测试');
    await Future<void>.delayed(Duration.zero);
    final failed = container.read(illustrationJobProvider)!;
    expect(failed.status, IllustrationJobStatus.failed);
    expect(failed.error, '接口挂了');

    final second = notifier.start(text: '另一段', label: '测试');
    expect(second, isNotNull);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(illustrationJobProvider)!.status,
      IllustrationJobStatus.done,
    );
  });

  test('a running job can be cancelled and its late result is ignored',
      () async {
    final completer = Completer<IllustrationResult>();
    final container = _container((onStage) => completer.future);
    addTearDown(container.dispose);
    final notifier = container.read(illustrationJobProvider.notifier);

    notifier.start(text: '一段文字', label: '测试');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(illustrationJobProvider)!.isRunning, isTrue);

    notifier.cancel();
    expect(container.read(illustrationJobProvider), isNull);

    completer.complete(_result());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(illustrationJobProvider), isNull);
  });

  test('a finished job can be dismissed but a running one cannot', () async {
    final completer = Completer<IllustrationResult>();
    final container = _container((onStage) => completer.future);
    addTearDown(container.dispose);
    final notifier = container.read(illustrationJobProvider.notifier);

    notifier.start(text: '一段文字', label: '测试');
    await Future<void>.delayed(Duration.zero);
    notifier.dismiss();
    expect(container.read(illustrationJobProvider), isNotNull);

    completer.complete(_result());
    await Future<void>.delayed(Duration.zero);
    notifier.dismiss();
    expect(container.read(illustrationJobProvider), isNull);
  });
}
