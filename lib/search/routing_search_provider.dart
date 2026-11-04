import '../distill/llm/llm_client.dart';
import 'free_web_search_provider.dart';
import 'search_config.dart';
import 'search_hit.dart';
import 'search_provider.dart';
import 'tavily_search_provider.dart';

/// Dispatches retrieval to the source the current settings name.
///
/// Both delegates are built on first use, so a 搜 call that never leaves the
/// free source never constructs a Tavily client (and vice versa). The config is
/// read through a callback rather than captured, so a settings change applies to
/// the next question without rebuilding anything.
class RoutingSearchProvider implements SearchProvider {
  RoutingSearchProvider({
    required this.config,
    SearchProvider? free,
    SearchProvider? tavily,
  })  : _freeOverride = free,
        _tavilyOverride = tavily;

  /// Read on every call, so settings changes take effect immediately.
  final SearchConfig Function() config;

  final SearchProvider? _freeOverride;
  final SearchProvider? _tavilyOverride;

  /// Memoized so the router holds one instance of each source and the
  /// "lazy" only means "not built before it is first needed".
  late final SearchProvider _free = _freeOverride ?? FreeWebSearchProvider();

  late final SearchProvider _tavily =
      _tavilyOverride ?? TavilySearchProvider(config: config);

  @override
  String get id => config().provider;

  @override
  bool get isConfigured => config().isConfigured;

  @override
  Future<List<SearchHit>> search(
    String query, {
    int count = 5,
    CancelToken? cancel,
  }) async {
    final settings = config();
    if (!settings.isConfigured) {
      throw SearchException('未配置联网搜索');
    }
    final delegate = settings.provider == SearchConfig.free ? _free : _tavily;
    return delegate.search(query, count: count, cancel: cancel);
  }
}
