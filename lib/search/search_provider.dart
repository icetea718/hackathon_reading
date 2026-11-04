import '../distill/llm/llm_client.dart';
import 'search_hit.dart';

class SearchException implements Exception {
  SearchException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'SearchException: $message';
}

/// Retrieval behind the 搜 shell.
///
/// The contract is deliberately retrieval-agnostic: the web implementation
/// returns [SearchHit]s with urls, a future "search my shelf" implementation
/// returns the same shape with locators.
abstract class SearchProvider {
  /// `'tavily'` for the web implementation, `'library'` for a future one.
  String get id;

  /// False means "do not call [search]": the user has not finished setup.
  bool get isConfigured;

  Future<List<SearchHit>> search(
    String query, {
    int count = 5,
    CancelToken? cancel,
  });
}
