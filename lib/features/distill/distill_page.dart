import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/distill.dart';
import 'distill_controller.dart';
import '../settings/settings_page.dart';

String stageLabel(DistillStage stage) {
  switch (stage) {
    case DistillStage.plan:
      return '规划片段';
    case DistillStage.map:
      return '逐段提炼';
    case DistillStage.reduce1:
      return '合并章节';
    case DistillStage.reduce2:
      return '归纳全书';
    case DistillStage.cards:
      return '生成卡片';
    case DistillStage.verify:
      return '校验引用';
  }
}

String statusLabel(DistillStatus status) {
  switch (status) {
    case DistillStatus.queued:
      return '等待开始';
    case DistillStatus.running:
      return '正在蒸馏';
    case DistillStatus.paused:
      return '已暂停';
    case DistillStatus.completed:
      return '已完成';
    case DistillStatus.failed:
      return '失败';
    case DistillStatus.canceled:
      return '已取消';
  }
}

class DistillPage extends ConsumerStatefulWidget {
  const DistillPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<DistillPage> createState() => _DistillPageState();
}

class _DistillPageState extends ConsumerState<DistillPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(distillControllerProvider(widget.bookId).notifier).pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(distillControllerProvider(widget.bookId));
    final artifacts = ref.watch(distillArtifactsProvider(widget.bookId));
    final loaded = artifacts is AsyncData<List<DistillArtifact>>
        ? artifacts.value
        : const <DistillArtifact>[];
    final controller =
        ref.read(distillControllerProvider(widget.bookId).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('书籍蒸馏')),
      body: DistillView(
        state: state,
        artifacts: loaded,
        onStart: controller.start,
        onResume: controller.resume,
        onPause: controller.pause,
        onCancel: controller.cancel,
      ),
    );
  }
}

/// Pure rendering of one [DistillState]; kept separate so widget tests can
/// drive every state without a running pipeline.
class DistillView extends StatelessWidget {
  const DistillView({
    super.key,
    required this.state,
    required this.artifacts,
    this.onStart,
    this.onResume,
    this.onPause,
    this.onCancel,
  });

  final DistillState state;
  final List<DistillArtifact> artifacts;
  final VoidCallback? onStart;
  final VoidCallback? onResume;
  final VoidCallback? onPause;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final job = state.job;
    final progress = state.progress;
    final done = progress?.doneUnits ?? job?.doneUnits ?? 0;
    final total = progress?.totalUnits ?? job?.totalUnits ?? 0;
    final stage = progress?.stage ?? job?.stage;
    final error = state.error ?? job?.errorText;

    if (job?.status == DistillStatus.completed) {
      return _ArtifactTabs(artifacts: artifacts);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          job == null ? '还没有开始蒸馏' : statusLabel(job.status),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (stage != null) ...[
          const SizedBox(height: 4),
          Text(stageLabel(stage)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Text('$done / $total'),
            const SizedBox(width: 12),
            Expanded(
              child: LinearProgressIndicator(
                value: total == 0 ? null : done / total,
              ),
            ),
          ],
        ),
        if (progress?.currentUnit != null) ...[
          const SizedBox(height: 8),
          Text(
            '正在处理 ${progress!.currentUnit}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (state.notice != null) ...[
          const SizedBox(height: 12),
          Text(
            state.notice!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          children: [
            if (!state.isRunning && job?.status != DistillStatus.paused)
              FilledButton(
                onPressed: onStart,
                child: const Text('开始蒸馏'),
              ),
            if (!state.isRunning && job?.status == DistillStatus.paused)
              FilledButton(
                onPressed: onResume,
                child: const Text('继续'),
              ),
            if (state.isRunning)
              OutlinedButton(
                onPressed: onPause,
                child: const Text('暂停'),
              ),
            if (state.isRunning || job?.status == DistillStatus.paused)
              TextButton(
                onPressed: onCancel,
                child: const Text('取消'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ArtifactTabs extends StatelessWidget {
  const _ArtifactTabs({required this.artifacts});

  final List<DistillArtifact> artifacts;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '总览'),
              Tab(text: '章节地图'),
              Tab(text: '卡片'),
              Tab(text: '语气'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ArtifactList(items: _ofKind(DistillArtifactKind.overview)),
                _ArtifactList(items: _ofKind(DistillArtifactKind.chapterGist)),
                _ArtifactList(items: _ofKind(DistillArtifactKind.card)),
                _ArtifactList(items: _ofKind(DistillArtifactKind.tone)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<DistillArtifact> _ofKind(DistillArtifactKind kind) =>
      artifacts.where((a) => a.kind == kind).toList();
}

class _ArtifactList extends StatelessWidget {
  const _ArtifactList({required this.items});

  final List<DistillArtifact> items;

  static String? _oneLiner(DistillArtifact artifact) {
    try {
      final decoded = jsonDecode(artifact.dataJson);
      if (decoded is Map && decoded['oneLiner'] is String) {
        return decoded['oneLiner'] as String;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final item = items[index];
        final oneLiner = _oneLiner(item);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleMedium),
            if (oneLiner != null) ...[
              const SizedBox(height: 4),
              Text(
                oneLiner,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 4),
            Text(item.body),
          ],
        );
      },
    );
  }
}

/// Opens the distillation page for [bookId].
Future<void> openDistillPage(BuildContext context, String bookId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DistillPage(bookId: bookId)),
  );
}

/// Opens the settings page; used by the distill page when no key is stored.
Future<void> openSettings(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
  );
}
