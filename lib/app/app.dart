import 'package:flutter/material.dart';

import '../features/library/library_page.dart';
import 'theme/app_theme.dart';

class BookApp extends StatelessWidget {
  const BookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 阅读器',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const LibraryPage(),
    );
  }
}
