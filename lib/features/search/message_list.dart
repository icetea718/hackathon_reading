import 'package:flutter/material.dart';

import '../../data/db/app_database.dart';
import '../../search/search_hit.dart';
import '../../search/search_step.dart';
import 'markdown_message.dart';
import 'steps_bar.dart';

/// Scrolling transcript for the 搜 shell.
class MessageList extends StatelessWidget {
  const MessageList({
    super.key,
    required this.messages,
    required this.streaming,
    required this.searching,
    required this.hits,
    required this.degraded,
    this.error,
    this.onRetry,
  });

  final List<ChatMessageRow> messages;
  final bool streaming;
  final bool searching;
  final List<SearchHit> hits;
  final bool degraded;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastAssistant = messages.isEmpty
        ? null
        : messages.lastWhere(
            (row) => row.role == 'assistant',
            orElse: () => messages.last,
          );
    final showCaret = streaming &&
        (lastAssistant?.content.isEmpty ?? true) &&
        SearchStep.listFromJson(lastAssistant?.stepsJson).isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        for (final row in messages)
          if (row.role == 'user')
            _UserBubble(text: row.content)
          else if (row.content.isNotEmpty || _stepsOf(row).isNotEmpty)
            _AssistantBlock(row: row),
        if (showCaret)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  searching ? '正在检索…' : '正在思考…',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (error != null && !streaming)
          _ErrorBar(message: error!, onRetry: onRetry)
        else if (degraded && !streaming)
          _DegradedBar(onRetry: onRetry)
        else if (hits.isNotEmpty && !streaming)
          _SourceBar(hits: hits),
      ],
    );
  }
}

List<SearchStep> _stepsOf(ChatMessageRow row) =>
    SearchStep.listFromJson(row.stepsJson);

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 12, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({required this.row});

  final ChatMessageRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _stepsOf(row);
    final interrupted = row.status == 'interrupted';
    final failed = row.status == 'failed';
    return Padding(
      padding: const EdgeInsets.only(top: 16, right: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (steps.isNotEmpty)
            StepsBar(steps: steps, streaming: row.status == 'streaming'),
          if (row.content.isNotEmpty) MarkdownMessage(data: row.content),
          if (interrupted || failed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                failed ? '生成失败' : '已停止',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('chat-error'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const Key('chat-error-retry'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _DegradedBar extends StatelessWidget {
  const _DegradedBar({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('chat-degraded'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本次未使用联网结果',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const Key('chat-retry'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _SourceBar extends StatelessWidget {
  const _SourceBar({required this.hits});

  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('chat-sources'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '来源',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hit in hits)
                Chip(
                  label: Text(
                    hit.title.isEmpty ? hit.source : hit.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                  avatar: const Icon(Icons.public, size: 14),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
