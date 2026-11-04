import 'package:flutter/material.dart';

import '../../search/search_config.dart';

/// 对话「联网」检索的来源。
///
/// [searchProvider] 就是存进 [SearchConfig.provider] 的那个 id。
enum SearchSource {
  /// 不检索，只用模型自己的知识。
  off,

  /// 必应网页结果，免 API Key。
  free,

  /// Tavily，质量更好但需要 API Key。
  tavily;

  String get searchProvider => switch (this) {
        SearchSource.off => SearchConfig.off,
        SearchSource.free => SearchConfig.free,
        SearchSource.tavily => SearchConfig.tavily,
      };
}

/// 让用户选检索来源的底部弹窗。
///
/// 返回用户选中的来源；手势下滑关掉面板时返回 null。
/// 选「关闭」返回的是 [SearchSource.off]，和 null 不是一回事。
Future<SearchSource?> showSearchSourceSheet(
  BuildContext context, {
  required SearchConfig config,
}) {
  return showModalBottomSheet<SearchSource>(
    context: context,
    // 让面板按内容高度撑开，不至于被默认的 9/16 屏高挤到溢出。
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SearchSourceSheet(current: _sourceFor(config.provider)),
  );
}

/// 把 [SearchConfig.provider] 里的 id 反查回枚举；认不出的 id 返回 null。
SearchSource? _sourceFor(String provider) {
  for (final source in SearchSource.values) {
    if (source.searchProvider == provider) return source;
  }
  return null;
}

class _SearchSourceSheet extends StatelessWidget {
  const _SearchSourceSheet({required this.current});

  /// 当前生效的来源，用来在对应那一行打勾；null 表示不打勾。
  final SearchSource? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      key: const Key('search-source-sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('联网搜索', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '选择检索来源；免费源不需要 API Key',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _option(
            context,
            source: SearchSource.off,
            title: '关闭',
            subtitle: '只用模型自己的知识',
          ),
          _option(
            context,
            source: SearchSource.free,
            title: '免费搜索',
            subtitle: '必应网页结果 · 免 Key · 偶尔不稳定',
          ),
          _option(
            context,
            source: SearchSource.tavily,
            title: 'Tavily',
            subtitle: '质量更好 · 需要在设置里填 API Key',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required SearchSource source,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      key: Key('search-source-${source.name}'),
      title: Text(title),
      subtitle: Text(subtitle),
      // 只有当前命中的那一行打勾。
      trailing: source == current ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(source),
    );
  }
}
