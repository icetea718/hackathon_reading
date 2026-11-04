import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Quotes selected in the reader that the reader has not sent yet.
final companionQuotesProvider = NotifierProvider<CompanionQuotes, List<String>>(
  CompanionQuotes.new,
);

class CompanionQuotes extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void add(String quote) => state = [...state, quote];

  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
  }

  void clear() => state = const [];
}

const companionQuoteHeader = '【引用】';
const _quotePrefix = '> ';

String composeCompanionMessage(List<String> quotes, String message) {
  final lines = <String>[
    for (final quote in quotes)
      if (quote.trim().isNotEmpty)
        for (final line in quote.replaceAll('\r\n', '\n').split('\n'))
          '$_quotePrefix$line',
  ];
  if (lines.isEmpty) return message;
  return '$companionQuoteHeader\n${lines.join('\n')}\n\n$message';
}

/// Split a stored companion message into its quoted excerpt (when present)
/// and the reader's own words.
({String? quote, String body}) parseCompanionMessage(String content) {
  final header = '$companionQuoteHeader\n';
  if (!content.startsWith(header)) {
    return (quote: null, body: content);
  }
  final rest = content.substring(header.length);
  final separator = rest.indexOf('\n\n');
  final quoted = separator < 0 ? rest : rest.substring(0, separator);
  final body = separator < 0 ? '' : rest.substring(separator + 2);
  final quote = quoted
      .split('\n')
      .map(
        (line) => line.startsWith(_quotePrefix)
            ? line.substring(_quotePrefix.length)
            : line,
      )
      .join('\n');
  return (quote: quote, body: body);
}
