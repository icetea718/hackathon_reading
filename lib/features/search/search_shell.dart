import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/book.dart';
import '../../search/search_book.dart';
import '../root/app_mode.dart';
import '../root/mode_switch.dart';
import '../settings/settings_page.dart';
import 'book_memory_sheet.dart';
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
    // The 'new' controller may already own this row once its first question
    // created it. Re-keying would start a second controller for the same
    // thread and hide the live stream.
    final current = ref.read(chatControllerProvider(_threadKey));
    if (current.threadId == id) return;
    setState(() => _threadKey = id);
  }

  void _newThread() {
    Navigator.maybePop(context);
    ref.read(chatControllerProvider(_threadKey).notifier).stop();
    ref
        .read(chatControllerProvider(ChatController.newThreadKey).notifier)
        .reset();
    setState(() => _threadKey = ChatController.newThreadKey);
  }

  void _threadDeleted(String id) {
    final key = _threadKey;
    final current = ref.read(chatControllerProvider(key));
    if (current.threadId != id) return;
    final controller = ref.read(chatControllerProvider(key).notifier);
    controller.stop();
    if (key == ChatController.newThreadKey) {
      controller.reset();
    } else {
      ref.invalidate(chatControllerProvider(key));
      ref
          .read(chatControllerProvider(ChatController.newThreadKey).notifier)
          .reset();
    }
    setState(() => _threadKey = ChatController.newThreadKey);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  void _openBookMemory(String bookId) {
    ref.invalidate(bookMemoryProvider(bookId));
    showBookMemorySheet(context, bookId);
  }

  Future<void> _pickBook() async {
    final picked = await showBookPicker(context);
    if (!mounted || picked == null) return;
    await _switchScope(picked);
  }

  /// Moves the shell into [bookId]'s archive (null = no book): the current
  /// stream stops, the sidebar follows the new scope, and the scope's most
  /// recent conversation opens. An empty scope shows a fresh conversation.
  Future<void> _switchScope(String? bookId) async {
    final key = _threadKey;
    ref.read(chatControllerProvider(key).notifier).stop();
    if (key == ChatController.newThreadKey) {
      ref.read(chatControllerProvider(key).notifier).reset();
    }
    final books = ref.read(searchBookProvider.notifier);
    if (bookId == null) {
      books.clear();
    } else {
      books.select(bookId);
    }

    final latest =
        await ref.read(chatThreadRepositoryProvider).latestForBook(bookId);
    if (!mounted) return;
    setState(() => _threadKey = latest?.id ?? ChatController.newThreadKey);
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(llmConfigProvider).asData?.value
            .isConfigured ??
        false;
    final webConfigured =
        ref.watch(searchConfigProvider).asData?.value.isEnabled ?? false;

    final chat = ref.watch(chatControllerProvider(_threadKey));

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
          onDeleted: _threadDeleted,
        );

        final chatColumn = Column(
          children: [
            _Header(
              wide: wide,
              bookSelected: bookId != null,
              onOpenBookMemory:
                  bookId == null ? null : () => _openBookMemory(bookId),
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
                          error: chat.error,
                          onRetry: () => _retry(),
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
              onClearBook: () => _switchScope(null),
              onStop: _stop,
              onSend: (text) => _send(text, webSearch: _webSearch && webConfigured),
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

  /// The controller is looked up when the action runs: a scope switch
  /// invalidates the current one, and a captured instance would be disposed.
  ChatController get _controller =>
      ref.read(chatControllerProvider(_threadKey).notifier);

  void _stop() => _controller.stop();

  Future<void> _send(String text, {required bool webSearch}) =>
      _controller.send(text, webSearch: webSearch);

  void _retry() {
    _controller.retry(webSearch: _webSearch);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.bookSelected,
    required this.onModeChanged,
    required this.onSettings,
    this.onOpenBookMemory,
  });

  final bool wide;
  final bool bookSelected;
  final ValueChanged<AppMode> onModeChanged;
  final VoidCallback onSettings;
  final VoidCallback? onOpenBookMemory;

  @override
  Widget build(BuildContext context) {
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
          const Spacer(),
          if (bookSelected)
            IconButton(
              key: const Key('search-book-memory'),
              tooltip: '本书资料',
              onPressed: onOpenBookMemory,
              icon: const Icon(Icons.auto_stories_outlined),
            ),
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
          ],
        ),
      ),
    );
  }
}
