import 'package:flutter_test/flutter_test.dart';
import 'package:coread/domain/services/epub_book_parser.dart';

import '../support/epub_fixture.dart';

void main() {
  test('extracts an img at its text position', () {
    final bytes = buildEpubBytes(
      docs: const [
        EpubFixtureDoc(
          href: 'chap1.xhtml',
          body: '<p>第一段</p><p><img src="images/pic.png"/></p><p>第二段</p>',
        ),
      ],
      images: const [
        EpubFixtureImage(
          href: 'images/pic.png',
          bytes: [1, 2, 3],
          mediaType: 'image/png',
        ),
      ],
      toc: const {'chap1.xhtml': '第一章'},
    );
    final chapter = parseEpubDocument(bytes).chapters.single;
    expect(chapter.contentText, '第一段\n第二段');
    expect(chapter.illustrations, hasLength(1));
    expect(chapter.illustrations.single.bytes, [1, 2, 3]);
    expect(chapter.illustrations.single.extension, 'png');
    expect(chapter.illustrations.single.offset, '第一段\n'.length);
  });

  test('extracts svg image href and skips a path-only svg', () {
    final bytes = buildEpubBytes(
      docs: const [
        EpubFixtureDoc(
          href: 'chap1.xhtml',
          body: '<p>前</p>'
              '<svg xmlns="http://www.w3.org/2000/svg">'
              '<image xlink:href="images/a.jpg" width="10" height="10"/>'
              '</svg>'
              '<svg><path d="M0 0"/></svg><p>后</p>',
        ),
      ],
      images: const [
        EpubFixtureImage(href: 'images/a.jpg', bytes: [7, 8]),
      ],
      toc: const {'chap1.xhtml': '第一章'},
    );
    final chapter = parseEpubDocument(bytes).chapters.single;
    expect(chapter.contentText, '前\n后');
    expect(chapter.illustrations, hasLength(1));
    expect(chapter.illustrations.single.bytes, [7, 8]);
    expect(chapter.illustrations.single.extension, 'jpg');
  });

  test('the declared cover is not treated as an inline illustration', () {
    final bytes = buildEpubBytes(
      docs: const [
        EpubFixtureDoc(
          href: 'chap1.xhtml',
          body: '<img src="images/cover.jpg"/><p>正文</p>',
        ),
      ],
      cover: const EpubFixtureCover(
        href: 'images/cover.jpg',
        bytes: [9, 9, 9],
      ),
      toc: const {'chap1.xhtml': '第一章'},
    );
    final chapter = parseEpubDocument(bytes).chapters.single;
    expect(chapter.illustrations, isEmpty);
    expect(chapter.contentText, '正文');
  });

  test('an image-only spine document attaches to the next chapter', () {
    final bytes = buildEpubBytes(
      docs: const [
        EpubFixtureDoc(href: 'front.xhtml', body: '<img src="images/p.png"/>'),
        EpubFixtureDoc(href: 'chap1.xhtml', body: '<p>正文</p>'),
      ],
      images: const [EpubFixtureImage(href: 'images/p.png', bytes: [4])],
      toc: const {'chap1.xhtml': '第一章'},
    );
    final document = parseEpubDocument(bytes);
    expect(document.chapters, hasLength(1));
    expect(document.chapters.single.illustrations.single.offset, 0);
    expect(document.chapters.single.contentText, '正文');
  });

  test('a trailing image-only spine document attaches to the last chapter', () {
    final bytes = buildEpubBytes(
      docs: const [
        EpubFixtureDoc(href: 'chap1.xhtml', body: '<p>正文</p>'),
        EpubFixtureDoc(href: 'end.xhtml', body: '<img src="images/p.png"/>'),
      ],
      images: const [EpubFixtureImage(href: 'images/p.png', bytes: [4])],
      toc: const {'chap1.xhtml': '第一章'},
    );
    final chapter = parseEpubDocument(bytes).chapters.single;
    expect(chapter.illustrations.single.offset, chapter.contentText.length);
  });

  test('TOC-split offsets are relative to the trimmed segment', () {
    final bytes = buildEpubBytes(
      docs: const [
        EpubFixtureDoc(
          href: 'chap1.xhtml',
          body: '<p>前言</p><h2 id="s1">第一节</h2><p>正文一</p>'
              '<h2 id="s2">第二节</h2><p><img src="images/p.png"/></p>'
              '<p>正文二</p>',
        ),
      ],
      images: const [EpubFixtureImage(href: 'images/p.png', bytes: [5])],
      tocEntries: const [
        EpubTocEntry(href: 'chap1.xhtml#s1', title: '第一节'),
        EpubTocEntry(href: 'chap1.xhtml#s2', title: '第二节'),
      ],
    );
    final second = parseEpubDocument(bytes).chapters[2];
    expect(second.contentText, '第二节\n正文二');
    expect(second.illustrations.single.offset, '第二节\n'.length);
  });

  test('skips data URIs, external URLs and missing files', () {
    final bytes = buildEpubBytes(
      docs: const [
        EpubFixtureDoc(
          href: 'chap1.xhtml',
          body: '<p>a</p><img src="data:image/png;base64,AA=="/>'
              '<img src="https://example.com/x.png"/>'
              '<img src="images/missing.png"/><p>b</p>',
        ),
      ],
      toc: const {'chap1.xhtml': '第一章'},
    );
    expect(parseEpubDocument(bytes).chapters.single.illustrations, isEmpty);
  });
}
