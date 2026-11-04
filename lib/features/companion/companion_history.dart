import 'package:flutter/material.dart';

import '../../domain/models/companion_chat.dart';

/// Relative label for a thread's last activity.
String formatCompanionTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';

  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(current.year, current.month, current.day);
  final clock = '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  if (day == today) return '今天 $clock';
  if (day == today.subtract(const Duration(days: 1))) return '昨天 $clock';
  if (time.year == current.year) return '${time.month}月${time.day}日';
  return '${time.year}年${time.month}月${time.day}日';
}

/// Threads for the whole book, grouped by chapter. The current chapter is
/// listed first and marked; older chapters open read-only.
class CompanionHistoryView extends StatefulWidget {
  const CompanionHistoryView({
    super.key,
    required this.threads,
    required this.currentChapterIndex,
    required this.loading,
    required this.onNewThread,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<CompanionThread> threads;
  final int currentChapterIndex;
  final bool loading;
  final VoidCallback onNewThread;
  final ValueChanged<CompanionThread> onOpen;
  final void Function(CompanionThread thread, String title) onRename;
  final ValueChanged<CompanionThread> onDelete;

  @override
  State<CompanionHistoryView> createState() => _CompanionHistoryViewState();
}

class _CompanionHistoryViewState extends State<CompanionHistoryView> {
  final TextEditingController _rename = TextEditingController();
  String? _editingId;

  @override
  void didUpdateWidget(covariant CompanionHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final editing = _editingId;
    if (editing != null && !widget.threads.any((t) => t.id == editing)) {
      _editingId = null;
    }
  }

  @override
  void dispose() {
    _rename.dispose();
    super.dispose();
  }

  List<MapEntry<int, List<CompanionThread>>> get _groups {
    final byChapter = <int, List<CompanionThread>>{};
    for (final thread in widget.threads) {
      byChapter.putIfAbsent(thread.chapterIndex, () => []).add(thread);
    }
    final indices = byChapter.keys.toList()..sort();
    final ordered = <int>[
      if (byChapter.containsKey(widget.currentChapterIndex))
        widget.currentChapterIndex,
      for (final index in indices)
        if (index != widget.currentChapterIndex) index,
    ];
    return [for (final index in ordered) MapEntry(index, byChapter[index]!)];
  }

  void _startRename(CompanionThread thread) {
    setState(() {
      _editingId = thread.id;
      _rename.text = thread.title;
      _rename.selection =
          TextSelection(baseOffset: 0, extentOffset: thread.title.length);
    });
  }

  void _saveRename(CompanionThread thread) {
    final title = _rename.text.trim();
    if (title.isEmpty) return;
    widget.onRename(thread, title);
    setState(() => _editingId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '对话历史',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  key: const Key('companion-new-thread'),
                  onPressed: widget.onNewThread,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建'),
                ),
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (widget.loading) {
      return const Center(child: Text('加载中…'));
    }
    if (widget.threads.isEmpty) {
      return const Center(child: Text('还没有对话'));
    }
    final groups = _groups;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final group in groups) ...[
          _GroupHeader(
            title: group.value.first.chapterTitle,
            current: group.key == widget.currentChapterIndex,
          ),
          for (final thread in group.value) _row(context, thread),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, CompanionThread thread) {
    if (_editingId == thread.id) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('companion-rename-field'),
                controller: _rename,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _saveRename(thread),
              ),
            ),
            IconButton(
              key: const Key('companion-rename-save'),
              tooltip: '保存',
              icon: const Icon(Icons.check),
              onPressed: () => _saveRename(thread),
            ),
            IconButton(
              key: const Key('companion-rename-cancel'),
              tooltip: '取消',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _editingId = null),
            ),
          ],
        ),
      );
    }

    final time = formatCompanionTime(thread.updatedAt);
    return ListTile(
      key: Key('companion-thread-${thread.id}'),
      onTap: () => widget.onOpen(thread),
      title: Text(
        thread.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$time · 共 ${thread.messageCount} 条'),
      trailing: PopupMenuButton<String>(
        key: Key('companion-thread-menu-${thread.id}'),
        tooltip: '对话操作',
        onSelected: (value) {
          if (value == 'rename') {
            _startRename(thread);
          } else if (value == 'delete') {
            widget.onDelete(thread);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            key: Key('companion-menu-rename'),
            value: 'rename',
            child: Text('重命名'),
          ),
          const PopupMenuItem<String>(
            key: Key('companion-menu-delete'),
            value: 'delete',
            child: Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.current});

  final String title;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: current
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              current ? '当前章' : '只读',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
