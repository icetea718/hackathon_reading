import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/search/search_source_sheet.dart';
import 'package:hackathon_reading/search/search_config.dart';

void main() {
  Future<SearchSource?> openSheet(WidgetTester tester, SearchConfig config) async {
    SearchSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          config: config,
          onPicked: (value) => picked = value,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('列出三个选项，当前项被标记', (tester) async {
    await openSheet(tester, const SearchConfig(provider: SearchConfig.free));
    expect(find.byKey(const Key('search-source-sheet')), findsOneWidget);
    expect(find.byKey(const Key('search-source-off')), findsOneWidget);
    expect(find.byKey(const Key('search-source-free')), findsOneWidget);
    expect(find.byKey(const Key('search-source-tavily')), findsOneWidget);
    expect(find.text('必应网页结果 · 免 Key · 偶尔不稳定'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('点免费源返回 free 并关闭面板', (tester) async {
    SearchSource? picked;
    await tester.pumpWidget(
      MaterialApp(home: _Opener(config: const SearchConfig(), onPicked: (v) => picked = v)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-source-free')));
    await tester.pumpAndSettle();

    expect(picked, SearchSource.free);
    expect(find.byKey(const Key('search-source-sheet')), findsNothing);
  });

  test('SearchSource 映射到配置 id', () {
    expect(SearchSource.off.searchProvider, SearchConfig.off);
    expect(SearchSource.free.searchProvider, SearchConfig.free);
    expect(SearchSource.tavily.searchProvider, SearchConfig.tavily);
  });
}

class _Opener extends StatelessWidget {
  const _Opener({required this.config, required this.onPicked});

  final SearchConfig config;
  final ValueChanged<SearchSource?> onPicked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final picked = await showSearchSourceSheet(context, config: config);
            onPicked(picked);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}
