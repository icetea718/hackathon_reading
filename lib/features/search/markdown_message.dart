import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Renders one assistant reply as Markdown.
///
/// Links are copied to the clipboard instead of opening a browser: the app
/// ships no `url_launcher`, and a dead tap is worse than a visible action.
class MarkdownMessage extends StatelessWidget {
  const MarkdownMessage({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge ?? const TextStyle();
    return SelectionArea(
      child: MarkdownBody(
        data: data,
        styleSheet: _styleSheet(theme, body),
        onTapLink: (text, href, title) => _copyLink(context, href),
      ),
    );
  }

  static MarkdownStyleSheet _styleSheet(ThemeData theme, TextStyle body) {
    final scheme = theme.colorScheme;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body.copyWith(height: 1.6),
      h1: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      h3: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      a: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      ),
      code: body.copyWith(
        fontFamily: 'monospace',
        fontSize: body.fontSize! - 1,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquote: body.copyWith(color: scheme.onSurfaceVariant),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant, width: 3)),
      ),
      listBullet: body,
      listIndent: 20,
      tableBorder: TableBorder.all(color: scheme.outlineVariant, width: 1),
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBody: body,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
    );
  }

  static void _copyLink(BuildContext context, String? href) {
    if (href == null || href.isEmpty) return;
    unawaitedCopy(href);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('链接已复制：$href')),
    );
  }

  static void unawaitedCopy(String value) {
    Clipboard.setData(ClipboardData(text: value));
  }
}
