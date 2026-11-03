import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/app.dart';

void main() {
  testWidgets('shows the empty library shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BookApp()));
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('还没有书，点右上角导入'), findsOneWidget);
  });
}
