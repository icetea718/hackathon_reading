import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/annotation_repository.dart';
import 'package:coread/data/repositories/book_repository.dart';
import 'package:coread/data/repositories/chapter_repository.dart';
import 'package:coread/data/repositories/progress_repository.dart';
import 'package:coread/data/storage/book_storage.dart';
import 'package:coread/domain/models/book.dart';
import 'package:coread/domain/services/book_service.dart';
import 'package:coread/domain/services/epub_book_parser.dart';

import '../support/epub_fixture.dart';

void main() {
  group('parseEpubDocument', () {
    test('reads EPUB3 nav titles and plain text in spine order', () {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/chapter1.xhtml',
            body: '<h1>第一章 开始</h1><p>Hello&nbsp;world &amp; more.</p>'
                '<p>第二段。</p>',
          ),
          EpubFixtureDoc(
            href: 'text/chapter2.xhtml',
            body: '<h2>第二章 继续</h2><p>正文二</p>',
          ),
        ],
        toc: const {
          'text/chapter1.xhtml': '第一章 开始',
          'text/chapter2.xhtml': '第二章 继续',
        },
      );

      final document = parseEpubDocument(bytes);
      const expectedFirst = '第一章 开始\nHello world & more.\n第二段。';

      expect(document.chapters.map((c) => c.title), ['第一章 开始', '第二章 继续']);
      expect(
        document.chapters.map((c) => c.contentText),
        [expectedFirst, '第二章 继续\n正文二'],
      );
      expect(document.chapters.first.startOffset, 0);
      expect(document.chapters.first.endOffset, expectedFirst.length);
      expect(
        document.chapters[1].startOffset,
        document.chapters[0].endOffset,
      );
      expect(
        document.chapters.last.endOffset,
        document.chapters.fold<int>(0, (sum, c) => sum + c.contentText.length),
      );
    });

    test('splits a spine document at nested NCX section anchors', () {
      final bytes = buildEpubBytes(
        useNcx: true,
        docs: const [
          EpubFixtureDoc(
            href: 'text/part1.xhtml',
            body: '<h1>第一部分</h1><h2 id="s1">择善</h2><p>甲。</p>'
                '<h2 id="s2">助产士</h2><p>乙。</p>',
          ),
          EpubFixtureDoc(
            href: 'text/part2.xhtml',
            body: '<h1>第二部分</h1><p>丙。</p>',
          ),
        ],
        tocEntries: const [
          EpubTocEntry(
            href: 'text/part1.xhtml',
            title: '第一部分',
            children: [
              EpubTocEntry(href: 'text/part1.xhtml#s1', title: '择善'),
              EpubTocEntry(href: 'text/part1.xhtml#s2', title: '助产士'),
            ],
          ),
          EpubTocEntry(href: 'text/part2.xhtml', title: '第二部分'),
        ],
      );

      final document = parseEpubDocument(bytes);

      expect(
        document.chapters.map((c) => c.title),
        ['第一部分', '择善', '助产士', '第二部分'],
      );
      expect(document.chapters.map((c) => c.level), [1, 2, 2, 1]);
      expect(document.chapters[0].contentText, '第一部分');
      expect(document.chapters[1].contentText, '择善\n甲。');
      expect(document.chapters[2].contentText, '助产士\n乙。');
      expect(document.chapters[3].contentText, '第二部分\n丙。');
      expect(
        document.chapters[1].startOffset,
        document.chapters[0].endOffset,
      );
      expect(
        document.chapters.last.endOffset,
        document.chapters.fold<int>(0, (sum, c) => sum + c.contentText.length),
      );
    });

    test('reads nested EPUB3 nav lists as sections', () {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/part1.xhtml',
            body: '<h1>第一卷</h1><h2 id="one">第一章 起</h2><p>甲。</p>'
                '<h2 id="two">第二章 承</h2><p>乙。</p>',
          ),
        ],
        tocEntries: const [
          EpubTocEntry(
            href: 'text/part1.xhtml',
            title: '第一卷',
            children: [
              EpubTocEntry(href: 'text/part1.xhtml#one', title: '第一章 起'),
              EpubTocEntry(href: 'text/part1.xhtml#two', title: '第二章 承'),
            ],
          ),
        ],
      );

      final document = parseEpubDocument(bytes);

      expect(
        document.chapters.map((c) => c.title),
        ['第一卷', '第一章 起', '第二章 承'],
      );
      expect(document.chapters.map((c) => c.level), [1, 2, 2]);
      expect(document.chapters[1].contentText, '第一章 起\n甲。');
    });

    test('reads EPUB2 NCX titles', () {
      final bytes = buildEpubBytes(
        useNcx: true,
        docs: const [
          EpubFixtureDoc(
            href: 'text/a.xhtml',
            body: '<p>甲章节正文</p>',
          ),
          EpubFixtureDoc(
            href: 'text/b.xhtml',
            body: '<p>乙章节正文</p>',
          ),
        ],
        toc: const {
          'text/a.xhtml': '甲章',
          'text/b.xhtml': '乙章',
        },
      );

      final document = parseEpubDocument(bytes);

      expect(document.chapters.map((c) => c.title), ['甲章', '乙章']);
      expect(document.chapters.map((c) => c.contentText), ['甲章节正文', '乙章节正文']);
    });

    test('skips nav and cover-only documents', () {
      final bytes = buildEpubBytes(
        includeNavInSpine: true,
        docs: const [
          EpubFixtureDoc(
            href: 'text/cover.xhtml',
            title: 'Cover',
            body: '<img src="cover.jpg" alt="Cover"/>',
          ),
          EpubFixtureDoc(
            href: 'text/chapter1.xhtml',
            body: '<p>正文一</p>',
          ),
        ],
        toc: const {'text/chapter1.xhtml': '第一章'},
      );

      final document = parseEpubDocument(bytes);

      expect(document.chapters, hasLength(1));
      expect(document.chapters.single.title, '第一章');
      expect(document.chapters.single.contentText, '正文一');
    });

    test('falls back to the file name when a spine item is not in the TOC', () {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/chapter1.xhtml',
            body: '<p>正文一</p>',
          ),
          EpubFixtureDoc(
            href: 'text/chapter2.xhtml',
            body: '<p>正文二</p>',
          ),
        ],
        toc: const {'text/chapter1.xhtml': '有目录的章节'},
      );

      final document = parseEpubDocument(bytes);

      expect(document.chapters.map((c) => c.title), ['有目录的章节', 'chapter2']);
    });

    test('throws EpubParseException for a malformed archive', () {
      expect(
        () => parseEpubDocument(utf8.encode('this is not a zip file')),
        throwsA(isA<EpubParseException>()),
      );
    });

    test('throws EpubParseException when the archive has no container', () {
      final archive = Archive()
        ..add(ArchiveFile.bytes(
          'mimetype',
          utf8.encode('application/epub+zip'),
        ));
      final bytes = ZipEncoder().encode(archive);

      expect(
        () => parseEpubDocument(bytes),
        throwsA(isA<EpubParseException>()),
      );
    });
  });

  group('EPUB comic pages', () {
    List<int> comicBytes({bool fixedLayout = false}) => buildEpubBytes(
          docs: const [
            EpubFixtureDoc(
              href: 'text/p1.xhtml',
              body: '<img src="../images/p1.jpg" alt="1"/>',
            ),
            EpubFixtureDoc(
              href: 'text/p2.xhtml',
              body: '<div><svg><image xlink:href="../images/p2.png"/></svg></div>',
            ),
          ],
          toc: const {'text/p1.xhtml': '第一话', 'text/p2.xhtml': '第二话'},
          images: const [
            EpubFixtureImage(href: 'images/p1.jpg', bytes: [1, 2, 3]),
            EpubFixtureImage(
              href: 'images/p2.png',
              bytes: [4, 5],
              mediaType: 'image/png',
            ),
          ],
          renditionLayout: fixedLayout ? 'pre-paginated' : null,
        );

    test('extracts raster pages in spine order with nav titles', () {
      final comic = parseEpubComic(comicBytes());

      expect(comic, isNotNull);
      expect(comic!.pages, hasLength(2));
      expect(comic.pages.map((page) => page.extension), ['jpg', 'png']);
      expect(comic.pages.map((page) => page.bytes), [
        [1, 2, 3],
        [4, 5],
      ]);
      expect(comic.pages.map((page) => page.title), ['第一话', '第二话']);
    });

    test('marks pre-paginated packages as fixed layout', () {
      final document = parseEpubDocument(comicBytes(fixedLayout: true));

      expect(document.fixedLayout, isTrue);
      expect(document.chapters, isEmpty);
    });

    test('returns null when the spine has no raster images', () {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(href: 'text/a.xhtml', body: '<p>正文</p>'),
        ],
      );

      expect(parseEpubComic(bytes), isNull);
    });
  });

  group('EPUB cover extraction', () {
    const coverBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 7, 8, 9];

    List<int> epubWithCover(EpubFixtureCover cover) => buildEpubBytes(
          docs: const [
            EpubFixtureDoc(
              href: 'text/chapter1.xhtml',
              body: '<p>正文</p>',
            ),
          ],
          toc: const {'text/chapter1.xhtml': '第一章'},
          cover: cover,
        );

    test('reads an EPUB3 cover-image item', () {
      final document = parseEpubDocument(epubWithCover(
        const EpubFixtureCover(
          href: 'images/cover.jpg',
          bytes: coverBytes,
        ),
      ));

      expect(document.cover, isNotNull);
      expect(document.cover!.bytes, coverBytes);
      expect(document.cover!.extension, 'jpg');
    });

    test('reads an EPUB2 meta cover', () {
      final document = parseEpubDocument(epubWithCover(
        const EpubFixtureCover(
          href: 'images/front.png',
          bytes: coverBytes,
          mediaType: 'image/png',
          id: 'front',
          useMeta: true,
        ),
      ));

      expect(document.cover?.bytes, coverBytes);
      expect(document.cover?.extension, 'png');
    });

    test('falls back to an image whose name contains cover', () {
      final document = parseEpubDocument(epubWithCover(
        const EpubFixtureCover(
          href: 'images/my-cover.webp',
          bytes: coverBytes,
          mediaType: 'image/webp',
          id: 'img1',
          declared: false,
        ),
      ));

      expect(document.cover?.extension, 'webp');
    });

    test('ignores SVG covers', () {
      final document = parseEpubDocument(epubWithCover(
        const EpubFixtureCover(
          href: 'images/cover.svg',
          bytes: coverBytes,
          mediaType: 'image/svg+xml',
        ),
      ));

      expect(document.cover, isNull);
    });

    test('has no cover when none is declared', () {
      final bytes = buildEpubBytes(docs: const [
        EpubFixtureDoc(href: 'text/a.xhtml', body: '<p>正文</p>'),
      ]);

      expect(parseEpubDocument(bytes).cover, isNull);
      expect(parseEpubCover(bytes), isNull);
    });

    test('parseEpubCover extracts the cover without reading the spine', () {
      final cover = parseEpubCover(epubWithCover(
        const EpubFixtureCover(
          href: 'images/cover.jpg',
          bytes: coverBytes,
        ),
      ));

      expect(cover?.bytes, coverBytes);
    });
  });

  group('BookService EPUB import', () {
    late Directory temp;
    late AppDatabase db;
    late BookRepository books;
    late ChapterRepository chapters;
    late BookService service;
    var nextId = 0;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('epub_import_test');
      db = AppDatabase(NativeDatabase.memory());
      books = BookRepository(db);
      chapters = ChapterRepository(db);
      service = BookService(
        books: books,
        chapters: chapters,
        progress: ProgressRepository(db),
        annotations: AnnotationRepository(db),
        storage: BookStorage(Directory('${temp.path}/books')),
        newId: () => 'epub-id-${nextId++}',
      );
    });

    tearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    test('import stores ordered chapters with plain text and offsets', () async {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/chapter1.xhtml',
            body: '<h1>第一章</h1><p>你好，世界。</p>',
          ),
          EpubFixtureDoc(
            href: 'text/chapter2.xhtml',
            body: '<h2>第二章</h2><p>再见。</p>',
          ),
        ],
        toc: const {
          'text/chapter1.xhtml': '第一章',
          'text/chapter2.xhtml': '第二章',
        },
      );
      final source = File('${temp.path}/我的小说.epub')
        ..writeAsBytesSync(bytes);

      final book = await service.importFile(source.path);
      final stored = await chapters.getForBook(book.id);

      expect(book.format, BookFormat.epub);
      expect(book.comic, isFalse);
      expect(stored.map((c) => c.title), ['第一章', '第二章']);
      expect(stored.map((c) => c.contentText), ['第一章\n你好，世界。', '第二章\n再见。']);
      expect(stored.first.startOffset, 0);
      expect(stored[1].startOffset, stored[0].endOffset);
      expect(
        stored.last.endOffset,
        stored.fold<int>(0, (sum, c) => sum + c.contentText.length),
      );
      expect(File(book.sourcePath).existsSync(), isTrue);

      for (final chapter in stored) {
        expect(
          chapter.contentText.length,
          chapter.endOffset - chapter.startOffset,
        );
      }
    });

    test('import persists the nested section levels', () async {
      final bytes = buildEpubBytes(
        useNcx: true,
        docs: const [
          EpubFixtureDoc(
            href: 'text/part1.xhtml',
            body: '<h1>第一部分</h1><h2 id="s1">择善</h2><p>甲。</p>',
          ),
        ],
        tocEntries: const [
          EpubTocEntry(
            href: 'text/part1.xhtml',
            title: '第一部分',
            children: [
              EpubTocEntry(href: 'text/part1.xhtml#s1', title: '择善'),
            ],
          ),
        ],
      );
      final source = File('${temp.path}/层级.epub')
        ..writeAsBytesSync(bytes);

      final book = await service.importFile(source.path);
      final stored = await chapters.getForBook(book.id);

      expect(stored.map((c) => c.title), ['第一部分', '择善']);
      expect(stored.map((c) => c.level), [1, 2]);
    });

    test('import saves an EPUB cover and stores its path', () async {
      const coverBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/chapter1.xhtml',
            body: '<p>你好</p>',
          ),
        ],
        toc: const {'text/chapter1.xhtml': '第一章'},
        cover: const EpubFixtureCover(
          href: 'images/cover.jpg',
          bytes: coverBytes,
        ),
      );
      final source = File('${temp.path}/带封面.epub')
        ..writeAsBytesSync(bytes);

      final book = await service.importFile(source.path);

      expect(book.coverPath, isNotNull);
      expect(book.coverPath, contains('covers'));
      expect(File(book.coverPath!).existsSync(), isTrue);
      expect(File(book.coverPath!).readAsBytesSync(), coverBytes);
      expect((await books.getAll()).single.coverPath, book.coverPath);
    });

    test('backfill extracts covers for books imported before cover support',
        () async {
      const coverBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 4, 5, 6];
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/chapter1.xhtml',
            body: '<p>旧书正文</p>',
          ),
        ],
        toc: const {'text/chapter1.xhtml': '第一章'},
        cover: const EpubFixtureCover(
          href: 'images/cover.jpg',
          bytes: coverBytes,
        ),
      );
      final source = File('${temp.path}/旧书.epub')
        ..writeAsBytesSync(bytes);
      await books.upsert(Book(
        id: 'old',
        title: '旧书',
        author: '',
        format: BookFormat.epub,
        sourcePath: source.path,
        addedAt: DateTime(2026, 1, 1),
      ));

      await service.backfillCovers();

      final updated = (await books.getAll()).single;
      expect(updated.coverPath, isNotNull);
      expect(File(updated.coverPath!).readAsBytesSync(), coverBytes);
    });

    test('deleting a book removes its cover file', () async {
      const coverBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 2, 4, 6];
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/chapter1.xhtml',
            body: '<p>正文</p>',
          ),
        ],
        toc: const {'text/chapter1.xhtml': '第一章'},
        cover: const EpubFixtureCover(
          href: 'images/cover.jpg',
          bytes: coverBytes,
        ),
      );
      final source = File('${temp.path}/待删.epub')..writeAsBytesSync(bytes);
      final book = await service.importFile(source.path);
      final coverPath = book.coverPath!;

      await service.deleteBook(book);

      expect(File(coverPath).existsSync(), isFalse);
    });

    test('imports an image-only EPUB as a comic with ordered pages', () async {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/p1.xhtml',
            body: '<img src="../images/p1.jpg" alt="1"/>',
          ),
          EpubFixtureDoc(
            href: 'text/p2.xhtml',
            body: '<img src="../images/p2.png" alt="2"/>',
          ),
        ],
        toc: const {'text/p1.xhtml': '第一话', 'text/p2.xhtml': '第二话'},
        images: const [
          EpubFixtureImage(href: 'images/p1.jpg', bytes: [1, 2, 3]),
          EpubFixtureImage(
            href: 'images/p2.png',
            bytes: [4, 5],
            mediaType: 'image/png',
          ),
        ],
      );
      final source = File('${temp.path}/漫画.epub')
        ..writeAsBytesSync(bytes);

      final book = await service.importFile(source.path);

      expect(book.comic, isTrue);
      expect(book.format, BookFormat.epub);
      expect(await chapters.getForBook(book.id), isEmpty);
      final pages = await service.storage.loadComicPages(book.id);
      expect(pages.map((page) => page.title), ['第一话', '第二话']);
      expect(File(pages[1].path).readAsBytesSync(), [4, 5]);
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).readAsBytesSync(), [1, 2, 3]);
      expect((await books.getAll()).single.comic, isTrue);
    });

    test('deleting a comic removes its page files', () async {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/p1.xhtml',
            body: '<img src="../images/p1.jpg" alt="1"/>',
          ),
        ],
        images: const [
          EpubFixtureImage(href: 'images/p1.jpg', bytes: [1, 2, 3]),
        ],
        renditionLayout: 'pre-paginated',
      );
      final source = File('${temp.path}/要删的漫画.epub')
        ..writeAsBytesSync(bytes);
      final book = await service.importFile(source.path);

      await service.deleteBook(book);

      expect(await service.storage.loadComicPages(book.id), isEmpty);
    });

    test('a pre-paginated EPUB with text is still read as a comic', () async {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/p1.xhtml',
            body: '<p>第 1 页</p><img src="../images/p1.jpg" alt="1"/>',
          ),
        ],
        images: const [
          EpubFixtureImage(href: 'images/p1.jpg', bytes: [7, 8]),
        ],
        renditionLayout: 'pre-paginated',
      );
      final source = File('${temp.path}/固定版式.epub')
        ..writeAsBytesSync(bytes);

      final book = await service.importFile(source.path);

      expect(book.comic, isTrue);
      expect(await chapters.getForBook(book.id), isEmpty);
      expect(
        await service.storage.loadComicPages(book.id),
        hasLength(1),
      );
    });

    test('malformed EPUB leaves no book row or copied file', () async {
      final source = File('${temp.path}/broken.epub')
        ..writeAsBytesSync(utf8.encode('definitely not an epub'));

      await expectLater(
        service.importFile(source.path),
        throwsA(isA<EpubParseException>()),
      );

      expect(await books.getAll(), isEmpty);
      final booksDir = Directory('${temp.path}/books');
      if (booksDir.existsSync()) {
        expect(booksDir.listSync(), isEmpty);
      }
    });

    test('EPUB with no readable content is rejected cleanly', () async {
      final bytes = buildEpubBytes(
        docs: const [
          EpubFixtureDoc(
            href: 'text/cover.xhtml',
            body: '<img src="cover.jpg" alt="Cover"/>',
          ),
        ],
      );
      final source = File('${temp.path}/empty.epub')
        ..writeAsBytesSync(bytes);

      await expectLater(
        service.importFile(source.path),
        throwsA(isA<EpubParseException>()),
      );

      expect(await books.getAll(), isEmpty);
      final booksDir = Directory('${temp.path}/books');
      if (booksDir.existsSync()) {
        expect(booksDir.listSync(), isEmpty);
      }
    });
  });
}
