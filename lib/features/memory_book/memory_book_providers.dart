import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../memory_book/memory_book_models.dart';
import '../../memory_book/memory_book_store.dart';

Future<Directory> _resolveMemoryBookRoot() async {
  final candidates = <Directory>[];

  // 首选 AppData；部分安全软件会拒绝新程序在这里建目录。
  try {
    final support = await getApplicationSupportDirectory();
    candidates.add(Directory(p.join(support.path, 'memory_books')));
  } catch (_) {
    // 继续尝试下一个位置。
  }

  // 其次用户文档目录；阅读器的数据库本来就在这里。
  try {
    final documents = await getApplicationDocumentsDirectory();
    candidates.add(
      Directory(p.join(documents.path, 'hackathon_reading_memory_books')),
    );
  } catch (_) {
    // 继续尝试下一个位置。
  }

  // 再次是 exe 同目录（绿色版/解压运行）。
  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    candidates.add(Directory(p.join(exeDir.path, 'memory_books')));
  } catch (_) {
    // 继续尝试下一个位置。
  }

  // 最后是系统临时目录，保证功能至少可用。
  candidates.add(
    Directory(p.join(Directory.systemTemp.path, 'hackathon_reading_memory_books')),
  );

  for (final directory in candidates) {
    try {
      await directory.create(recursive: true);
      return directory;
    } catch (_) {
      // 换下一个候选目录。
    }
  }

  throw StateError(
    '找不到可写的回忆录目录。请检查安全软件是否拦截了 AppData/文档目录。',
  );
}

final memoryBookStoreProvider = FutureProvider<MemoryBookStore>((ref) async {
  final root = await _resolveMemoryBookRoot();
  final store = MemoryBookStore(root);
  await store.init();
  ref.onDispose(() {
    unawaited(store.dispose());
  });
  return store;
});

final memoryBookListProvider = StreamProvider<List<MemoryBook>>((ref) async* {
  final store = await ref.watch(memoryBookStoreProvider.future);
  yield* store.watch();
});
