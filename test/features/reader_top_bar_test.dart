import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/app/theme/app_theme.dart';
import 'package:coread/features/reader/reader_top_bar.dart';

void main() {
  testWidgets('the reader title uses the shared title role', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          appBar: ReaderTopBar(
            title: '书名',
            background: Colors.white,
            foreground: Colors.black,
            pinned: false,
            onTogglePinned: () {},
            bookmarked: false,
            onToggleBookmark: () {},
            onOpenAnnotations: () {},
            onOpenToc: () {},
            onOpenCompanion: () {},
            onOpenReaderSettings: () {},
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('书名'));
    expect(title.style?.fontSize, 16);
    expect(title.style?.fontWeight, FontWeight.w600);
  });
}
