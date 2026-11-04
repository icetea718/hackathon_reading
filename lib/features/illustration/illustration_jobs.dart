import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../illustration/illustration_models.dart';
import '../../illustration/illustration_service.dart';

enum IllustrationJobStatus { running, done, failed }

/// One illustration generation, owned outside the page that started it so it
/// keeps running while the reader keeps reading.
class IllustrationJob {
  const IllustrationJob({
    required this.id,
    required this.text,
    required this.label,
    required this.status,
    this.stage,
    this.result,
    this.error,
  });

  final String id;
  final String text;
  final String label;
  final IllustrationJobStatus status;
  final IllustrationStage? stage;
  final IllustrationResult? result;
  final String? error;

  bool get isRunning => status == IllustrationJobStatus.running;
}

final illustrationJobProvider =
    NotifierProvider<IllustrationJobController, IllustrationJob?>(
  IllustrationJobController.new,
);

class IllustrationJobController extends Notifier<IllustrationJob?> {
  IllustrationService? _activeService;

  @override
  IllustrationJob? build() => null;

  /// Starts a generation in the background and returns its id, or null when
  /// one is already running.
  String? start({required String text, required String label}) {
    if (state?.isRunning ?? false) return null;

    final input = text.trim();
    final id = const Uuid().v4();
    state = IllustrationJob(
      id: id,
      text: input,
      label: label,
      status: IllustrationJobStatus.running,
      stage: IllustrationStage.planning,
    );
    unawaited(_run(id, input));
    return id;
  }

  Future<void> _run(String id, String input) async {
    IllustrationService? service;
    try {
      final config = await ref.read(illustrationConfigProvider.future);
      final llm = await ref.read(llmConfigProvider.future);
      final effective = config.resolve(llm);
      if (!effective.isConfigured) {
        throw IllustrationException(
          '还没有配置插画服务。请到设置里填写生图接口、API Key 和图像模型。',
        );
      }
      service = ref.read(illustrationServiceFactoryProvider)(effective);
      _activeService = service;
      final result = await service.generate(
        input,
        onStage: (stage) {
          final job = state;
          if (job == null || job.id != id || !job.isRunning) return;
          state = IllustrationJob(
            id: job.id,
            text: job.text,
            label: job.label,
            status: job.status,
            stage: stage,
          );
        },
      );
      final job = state;
      if (job != null && job.id == id) {
        state = IllustrationJob(
          id: job.id,
          text: job.text,
          label: job.label,
          status: IllustrationJobStatus.done,
          result: result,
        );
      }
    } catch (error) {
      final job = state;
      if (job != null && job.id == id) {
        state = IllustrationJob(
          id: job.id,
          text: job.text,
          label: job.label,
          status: IllustrationJobStatus.failed,
          error: error.toString(),
        );
      }
    } finally {
      if (identical(_activeService, service)) _activeService = null;
      service?.dispose();
    }
  }

  /// Stops the running job and drops its in-flight result.
  void cancel() {
    if (!(state?.isRunning ?? false)) return;
    state = null;
    final service = _activeService;
    _activeService = null;
    service?.dispose();
  }

  void dismiss() {
    if (state?.isRunning ?? false) return;
    state = null;
  }
}
