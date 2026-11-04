import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/illustration/illustration_composer_page.dart';
import '../features/illustration/illustration_jobs.dart';
import '../features/root/root_view.dart';
import 'app_keys.dart';
import 'theme/app_theme.dart';

class BookApp extends ConsumerWidget {
  const BookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<IllustrationJob?>(illustrationJobProvider, (previous, next) {
      final job = next;
      if (job == null ||
          job.status != IllustrationJobStatus.done ||
          previous?.id != job.id ||
          !(previous?.isRunning ?? false)) {
        return;
      }
      appScaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('插画已生成'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () => appNavigatorKey.currentState?.push(
                MaterialPageRoute<void>(
                  builder: (_) => IllustrationComposerPage(
                    jobId: job.id,
                    initialText: job.text,
                    contextLabel: job.label,
                  ),
                ),
              ),
            ),
          ),
        );
    });

    return MaterialApp(
      title: 'AI 阅读器',
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const RootView(),
    );
  }
}
