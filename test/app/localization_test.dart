import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/app.dart';

void main() {
  testWidgets('the built-in text menus speak Chinese', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BookApp()));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('今天想做什么？'));
    final labels = MaterialLocalizations.of(context);

    expect(labels.copyButtonLabel, '复制');
    expect(labels.selectAllButtonLabel, '全选');
  });
}
