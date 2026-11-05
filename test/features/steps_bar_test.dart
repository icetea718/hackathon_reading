import 'package:coread/features/search/steps_bar.dart';
import 'package:coread/search/search_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

const _search = SearchStep(
  tool: 'search_in_book',
  summary: '检索「雨」',
  chapters: [3, 7],
  hits: 2,
  ms: 120,
);

const _read = SearchStep(
  tool: 'get_chapter',
  summary: '读第 12 章',
  chapters: [12],
  hits: 1,
  ms: 80,
);

const _notice = SearchStep(
  tool: 'notice',
  summary: '当前模型不支持工具检索，已用摘要回答',
  chapters: [],
  hits: 0,
  ms: 0,
);

void main() {
  testWidgets('折叠态显示次数与章号，展开后列出每一步', (tester) async {
    await tester.pumpWidget(
      _host(const StepsBar(steps: [_search, _read], streaming: false)),
    );

    expect(find.textContaining('检索 2 次'), findsOneWidget);
    expect(find.textContaining('第 3、7、12 章'), findsOneWidget);
    expect(find.textContaining('检索「雨」'), findsNothing);

    await tester.tap(find.byKey(const Key('steps-bar-toggle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('检索「雨」'), findsOneWidget);
    expect(find.textContaining('读第 12 章'), findsOneWidget);
    expect(find.textContaining('120 ms'), findsOneWidget);
  });

  testWidgets('运行中显示最后一步并带进度圈', (tester) async {
    await tester.pumpWidget(
      _host(const StepsBar(steps: [_search], streaming: true)),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('检索「雨」'), findsOneWidget);
    expect(find.byKey(const Key('steps-bar-toggle')), findsNothing);
  });

  testWidgets('运行中还没有步骤时提示正在判断', (tester) async {
    await tester.pumpWidget(_host(const StepsBar(steps: [], streaming: true)));

    expect(find.textContaining('正在判断要不要翻书'), findsOneWidget);
  });

  testWidgets('notice 条目渲染成灰字提示', (tester) async {
    await tester.pumpWidget(
      _host(const StepsBar(steps: [_notice], streaming: false)),
    );

    expect(find.textContaining('不支持工具检索'), findsOneWidget);
  });

  testWidgets('没有步骤时什么都不画', (tester) async {
    await tester.pumpWidget(_host(const StepsBar(steps: [], streaming: false)));

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('章号超过六个时截断', (tester) async {
    await tester.pumpWidget(
      _host(
        const StepsBar(
          steps: [
            SearchStep(
              tool: 'search_in_book',
              summary: '检索「雨」',
              chapters: [1, 2, 3, 4, 5, 6, 7, 8],
              hits: 8,
              ms: 10,
            ),
          ],
          streaming: false,
        ),
      ),
    );

    expect(find.textContaining('第 1、2、3、4、5、6… 章'), findsOneWidget);
  });
}
