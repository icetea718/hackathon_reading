import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/annotation_repository.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/category_repository.dart';
import 'package:coread/data/repositories/chapter_repository.dart';
import 'package:coread/data/repositories/companion_chat_repository.dart';
import 'package:coread/data/repositories/progress_repository.dart';
import 'package:coread/data/storage/book_storage.dart';
import 'package:coread/domain/models/annotation.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/models/chapter.dart';
import 'package:coread/domain/models/companion_chat.dart';
import 'package:coread/domain/services/book_service.dart';
import 'package:coread/domain/services/epub_book_parser.dart';

import '../support/epub_fixture.dart';

class _FailingStorage extends BookStorage {
  _FailingStorage(super.booksRoot);

  @override
  Future<void> saveIllustrations(
    String id,
    List<
            ({
              int chapterIndex,
              int offset,
              int width,
              int height,
              List<int> bytes,
              String extension,
            })>
        images,
  ) async {
    throw const FileSystemException('disk full');
  }
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late BookRepository repo;
  late BookService service;
  var nextId = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('book_service_test');
    db = AppDatabase(NativeDatabase.memory());
    repo = BookRepository(db);
    nextId = 0;
    service = BookService(
      books: repo,
      chapters: ChapterRepository(db),
      progress: ProgressRepository(db),
      annotations: AnnotationRepository(db),
      storage: BookStorage(Directory('${temp.path}/books')),
      companionChats: CompanionChatRepository(db),
      newId: () => 'id-${nextId++}',
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<({int width, int height})?> fakeSize(List<int> bytes) async {
    if (bytes.isEmpty || bytes.first == 0) return null;
    return bytes.first == 1
        ? (width: 800, height: 1200)
        : (width: 10, height: 10);
  }

  BookService serviceWithSizes() => BookService(
        books: repo,
        chapters: ChapterRepository(db),
        progress: ProgressRepository(db),
        annotations: AnnotationRepository(db),
        storage: BookStorage(Directory('${temp.path}/books')),
        newId: () => 'id-${nextId++}',
        imageSize: fakeSize,
      );

  List<int> illustratedEpub() => buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'chap1.xhtml',
            body: '<p>前</p><img src="images/big.png"/>'
                '<img src="images/broken.png"/><p>后</p>',
          ),
          EpubFixtureDoc(
            href: 'chap2.xhtml',
            body: '<img src="images/small.png"/><p>二</p>',
          ),
        ],
        images: const [
          EpubFixtureImage(
            href: 'images/big.png',
            bytes: [1],
            mediaType: 'image/png',
          ),
          EpubFixtureImage(
            href: 'images/broken.png',
            bytes: [0],
            mediaType: 'image/png',
          ),
          EpubFixtureImage(
            href: 'images/small.png',
            bytes: [2],
            mediaType: 'image/png',
          ),
        ],
        toc: const {'chap1.xhtml': '第一章', 'chap2.xhtml': '第二章'},
      );

  Future<Book> seedStoredEpub({String? storedTitleOverride}) async {
    final bytes = illustratedEpub();
    final file = File('${temp.path}/stored.epub')
      ..writeAsBytesSync(bytes);
    final document = parseEpubDocument(bytes);
    final book = Book(
      id: 'old',
      title: '旧书',
      author: '',
      format: BookFormat.epub,
      sourcePath: file.path,
      addedAt: DateTime(2026, 1, 1),
    );
    await repo.upsert(book);
    await ChapterRepository(db).replaceForBook('old', [
      for (var i = 0; i < document.chapters.length; i++)
        Chapter(
          id: 'old-c$i',
          bookId: 'old',
          index: i,
          title: i == 0 && storedTitleOverride != null
              ? storedTitleOverride
              : document.chapters[i].title,
          startOffset: document.chapters[i].startOffset,
          endOffset: document.chapters[i].endOffset,
          contentText: document.chapters[i].contentText,
          level: document.chapters[i].level,
        ),
    ]);
    return book;
  }

  test('import saves illustrations and skips thumbs and undecodable bytes',
      () async {
    final source = File('${temp.path}/pic.epub')
      ..writeAsBytesSync(illustratedEpub());
    final book = await serviceWithSizes().importFile(source.path);

    final images = await service.storage.loadIllustrations(book.id);
    expect(images, hasLength(1));
    expect(images!.single.chapterIndex, 0);
    expect(images.single.width, 800);
    expect(images.single.height, 1200);
    expect(images.single.offset, '前\n'.length);
  });

  test('import keeps the book when illustration saving fails', () async {
    final source = File('${temp.path}/fail.epub')
      ..writeAsBytesSync(illustratedEpub());
    final failing = BookService(
      books: repo,
      chapters: ChapterRepository(db),
      progress: ProgressRepository(db),
      annotations: AnnotationRepository(db),
      storage: _FailingStorage(Directory('${temp.path}/failing-books')),
      newId: () => 'fail-${nextId++}',
      imageSize: fakeSize,
    );

    final book = await failing.importFile(source.path);

    expect((await ChapterRepository(db).getForBook(book.id)), isNotEmpty);
    expect(await failing.storage.loadIllustrations(book.id), isNull);
  });

  test('ensureIllustrations backfills an old book once', () async {
    final book = await seedStoredEpub();
    final sized = serviceWithSizes();

    await sized.ensureIllustrations(book);

    final images = await service.storage.loadIllustrations(book.id);
    expect(images, hasLength(1));
    expect(images!.single.offset, '前\n'.length);
    expect(images.single.width, 800);

    File(book.sourcePath).deleteSync();
    await sized.ensureIllustrations(book);
    expect(await service.storage.loadIllustrations(book.id), hasLength(1));
  });

  test('ensureIllustrations writes an empty manifest when chapters no longer '
      'match', () async {
    final book = await seedStoredEpub(storedTitleOverride: '旧规则');

    await serviceWithSizes().ensureIllustrations(book);

    expect(await service.storage.loadIllustrations(book.id), isEmpty);
    final stored = await ChapterRepository(db).getForBook(book.id);
    expect(stored.first.title, '旧规则');
  });

  test('ensureIllustrations leaves no manifest when the source is missing',
      () async {
    final book = Book(
      id: 'gone',
      title: '丢书',
      author: '',
      format: BookFormat.epub,
      sourcePath: '${temp.path}/gone.epub',
      addedAt: DateTime(2026, 1, 1),
    );
    await repo.upsert(book);

    await serviceWithSizes().ensureIllustrations(book);

    expect(await service.storage.loadIllustrations('gone'), isNull);
  });

  test('comic imports do not write an illustration manifest', () async {
    final source = File('${temp.path}/comic.epub')
      ..writeAsBytesSync(buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'page1.xhtml',
            body: '<img src="images/page.jpg"/>',
          ),
        ],
        images: const [
          EpubFixtureImage(href: 'images/page.jpg', bytes: [1]),
        ],
        renditionLayout: 'pre-paginated',
      ));

    final book = await serviceWithSizes().importFile(source.path);

    expect(book.comic, isTrue);
    expect(await service.storage.loadIllustrations(book.id), isNull);
  });

  test('deleteBook removes the illustrations directory', () async {
    final source = File('${temp.path}/del.epub')
      ..writeAsBytesSync(illustratedEpub());
    final book = await serviceWithSizes().importFile(source.path);
    expect(await service.storage.hasIllustrationIndex(book.id), isTrue);

    await service.deleteBook(book);

    expect(await service.storage.hasIllustrationIndex(book.id), isFalse);
  });

  test('imports an uppercase TXT with a Chinese name', () async {
    final source = File('${temp.path}/我的 小说.TXT')
      ..writeAsStringSync('第一章 开始\n内容');
    final book = await service.importFile(source.path);
    expect(book.format, BookFormat.txt);
    expect(book.title, '我的 小说');
    expect(File(book.sourcePath).readAsStringSync(), contains('第一章'));
    expect((await repo.getAll()).single.id, book.id);
    expect(book.sourcePath, endsWith('${book.id}.txt'));
  });

  test('rejects unsupported extensions without recording a book', () async {
    final source = File('${temp.path}/a.doc')..writeAsStringSync('x');
    await expectLater(service.importFile(source.path),
        throwsA(isA<UnsupportedBookFormatException>()));
    expect(await repo.getAll(), isEmpty);
  });

  test('rejects empty files without recording a book', () async {
    final source = File('${temp.path}/empty.txt')..writeAsBytesSync([]);
    await expectLater(service.importFile(source.path),
        throwsA(isA<EmptyBookException>()));
    expect(await repo.getAll(), isEmpty);
  });

  test('delete removes the copied file and the record', () async {
    final source = File('${temp.path}/t.txt')..writeAsStringSync('x');
    final book = await service.importFile(source.path);
    expect(File(book.sourcePath).existsSync(), isTrue);
    await service.deleteBook(book);
    expect(File(book.sourcePath).existsSync(), isFalse);
    expect(await repo.getAll(), isEmpty);
  });

  test('rejects importing the same file twice', () async {
    final source = File('${temp.path}/same.txt')
      ..writeAsStringSync('第一章 开始\n内容');
    final first = await service.importFile(source.path);

    await expectLater(
      service.importFile(source.path),
      throwsA(isA<DuplicateBookException>()),
    );

    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.single.id, first.id);
    expect(Directory('${temp.path}/books').listSync(), hasLength(1));
  });

  test('backfills hashes for books imported before deduplication', () async {
    final source = File('${temp.path}/legacy.txt')
      ..writeAsStringSync('旧书内容');
    final book = await service.importFile(source.path);
    await repo.upsert(Book(
      id: book.id,
      title: book.title,
      author: book.author,
      format: book.format,
      sourcePath: book.sourcePath,
      addedAt: book.addedAt,
    ));
    expect((await repo.getById(book.id))!.contentHash, isNull);

    await service.backfillContentHashes();

    expect((await repo.getById(book.id))!.contentHash, isNotNull);
    await expectLater(
      service.importFile(source.path),
      throwsA(isA<DuplicateBookException>()),
    );
  });

  test('does not treat different files as duplicates', () async {
    final one = File('${temp.path}/one.txt')
      ..writeAsStringSync('第一章 开始\n内容一');
    final two = File('${temp.path}/two.txt')
      ..writeAsStringSync('第一章 开始\n内容二');

    await service.importFile(one.path);
    await service.importFile(two.path);

    expect(await repo.getAll(), hasLength(2));
  });

  test('delete removes annotations for the book', () async {
    final source = File('${temp.path}/t.txt')..writeAsStringSync('x');
    final book = await service.importFile(source.path);
    final annotations = AnnotationRepository(db);
    await annotations.upsert(Annotation(
      id: 'a1',
      bookId: book.id,
      type: AnnotationType.bookmark,
      anchorStart: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    await service.deleteBook(book);
    expect(await annotations.getForBook(book.id), isEmpty);
  });

  test('deleting a book removes its category memberships', () async {
    final categories = CategoryRepository(db);
    final category = await categories.create('科幻');
    await repo.upsert(Book(
      id: 'b1',
      title: '书',
      author: '',
      format: BookFormat.txt,
      sourcePath: 'C:/books/b1.txt',
      addedAt: DateTime(2026, 1, 1),
    ));
    await categories.addBook('b1', category.id);
    final service = BookService(
      books: repo,
      chapters: ChapterRepository(db),
      progress: ProgressRepository(db),
      annotations: AnnotationRepository(db),
      storage: BookStorage(Directory('${temp.path}/books')),
      categories: categories,
    );

    await service.deleteBook((await repo.getById('b1'))!);

    expect(await categories.watchMemberships().first, isEmpty);
  });

  test('deleting a book removes its companion conversations', () async {
    final source = File('${temp.path}/chat.txt')
      ..writeAsStringSync('第一章 开始\n内容');
    final book = await service.importFile(source.path);
    final chats = CompanionChatRepository(db);
    final thread = await chats.createThread(
      bookId: book.id,
      chapterIndex: 0,
      chapterTitle: '第一章',
    );
    await chats.appendMessage(
      threadId: thread.id,
      role: CompanionRole.user,
      content: '福贵是谁？',
    );

    await service.deleteBook(book);

    expect(await chats.threadsForBook(book.id), isEmpty);
    expect(await chats.messagesForThread(thread.id), isEmpty);
  });
}
