import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/book.dart';
import '../../search/search_book.dart';
import '../root/app_mode.dart';
import '../root/mode_switch.dart';
import '../settings/settings_page.dart';
import 'book_picker.dart';
import 'chat_composer.dart';
import 'chat_controller.dart';
import 'conversation_sidebar.dart';
import 'message_list.dart';

/// The 搜 shell: one agent conversation plus its history.
class SearchShell extends ConsumerStatefulWidget {
  const SearchShell({super.key});

  /// Below this width the history moves into a drawer.
  static const double wideBreakpoint = 1000;

  @override
  ConsumerState<SearchShell> createState() => _SearchShellState();
}

class _SearchShellState extends ConsumerState<SearchShell> {
  String _threadKey = ChatController.newThreadKey;
  bool _webSearch = false;

  @override
  void initState() {
    super.initState();
    // A row still marked streaming was left behind by a crash or a kill; the
    // request it belonged to is long gone.
    Future.microtask(
      () => ref.read(chatMessageRepositoryProvider).markStreamingAsInterrupted(),
    );
  }

  void _openThread(String id) {
    Navigator.maybePop(context);
    setState(() => _threadKey = id);
  }

  void _newThread() {
    Navigator.maybePop(context);
    ref.invalidate(chatControllerProvider(ChatController.newThreadKey));
    setState(() => _threadKey = ChatController.newThreadKey);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> _pickBook() async {
    final picked = await showBookPicker(context);
    if (!mounted || picked == null) return;
    ref.read(searchBookProvider.notifier).select(picked);
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(llmConfigProvider).asData?.value
            .isConfigured ??
        false;
    final webConfigured =
        ref.watch(searchConfigProvider).asData?.value.isEnabled ?? false;

    final chat = ref.watch(chatControllerProvider(_threadKey));
    final controller = ref.read(chatControllerProvider(_threadKey).notifier);

    final bookId = ref.watch(searchBookProvider);
    final books = ref.watch(bookListProvider).asData?.value ?? const <Book>[];
    String? bookTitle;
    for (final book in books) {
      if (book.id == bookId) bookTitle = book.title;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= SearchShell.wideBreakpoint;
        final sidebar = ConversationSidebar(
          activeThreadId: chat.threadId,
          onPick: _openThread,
          onNew: _newThread,
        );

        final chatColumn = Column(
          children: [
            _Header(
              wide: wide,
              onModeChanged: (mode) =>
                  ref.read(modeProvider.notifier).select(mode),
              onSettings: _openSettings,
            ),
            const Divider(height: 1),
            Expanded(
              child: !configured
                  ? _Unconfigured(onSettings: _openSettings)
                  : chat.messages.isEmpty
                      ? const _EmptyState()
                      : MessageList(
                          messages: chat.messages,
                          streaming: chat.streaming,
                          searching: chat.searching,
                          hits: chat.hits,
                          degraded: chat.degraded,
                          onRetry: () => _retry(controller, chat),
                        ),
            ),
            ChatComposer(
              enabled: configured,
              streaming: chat.streaming,
              webEnabled: _webSearch,
              webConfigured: webConfigured,
              onWebChanged: (value) => setState(() => _webSearch = value),
              bookTitle: bookTitle,
              onPickBook: _pickBook,
              onClearBook: () => ref.read(searchBookProvider.notifier).clear(),
              onStop: controller.stop,
              onSend: (text) =>
                  controller.send(text, webSearch: _webSearch && webConfigured),
            ),
          ],
        );

        return Scaffold(
          key: const Key('search-shell'),
          drawer: wide ? null : Drawer(child: sidebar),
          body: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sidebar,
                    const VerticalDivider(width: 1),
                    Expanded(child: chatColumn),
                  ],
                )
              : chatColumn,
        );
      },
    );
  }

  void _retry(ChatController controller, ChatState chat) {
    for (final row in chat.messages.reversed) {
      if (row.role == 'user') {
        controller.send(row.content, webSearch: _webSearch);
        return;
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.onModeChanged,
    required this.onSettings,
  });

  final bool wide;
  final ValueChanged<AppMode> onModeChanged;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Builder(
            builder: (inner) => ModeSwitch(
              mode: AppMode.search,
              axis: Axis.horizontal,
              keyPrefix: 'search',
              onChanged: onModeChanged,
            ),
          ),
          const SizedBox(width: 8),
          if (!wide)
            Builder(
              builder: (inner) => IconButton(
                tooltip: '历史对话',
                onPressed: () => Scaffold.of(inner).openDrawer(),
                icon: const Icon(Icons.menu),
              ),
            ),
          Text('搜', style: theme.textTheme.titleMedium),
          const Spacer(),
          IconButton(
            key: const Key('chat-settings'),
            tooltip: '设置',
            onPressed: onSettings,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }
}

class _Unconfigured extends StatelessWidget {
  const _Unconfigured({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.key_off_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('还没配置模型', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '填上 base URL、模型名和 API Key 就能开始聊',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onSettings, child: const Text('去设置')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  static const _suggestions = [
    '最近 AI 领域有什么值得关注的事？',
    '帮我对比一下 Flutter 和 React Native',
    '解释一下什么是向量数据库',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '今天想查点什么？',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '打开「联网」会先检索网页，答案后面附上来源；'
              '点「选择书」可以让回答只依据书架里的某一本书。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final text in _suggestions)
                  ActionChip(label: Text(text), onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
