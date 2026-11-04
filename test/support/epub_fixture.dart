import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// A content document to place in the generated EPUB fixture.
class EpubFixtureDoc {
  const EpubFixtureDoc({
    required this.href,
    required this.body,
    this.id,
    this.title = '',
    this.inSpine = true,
  });

  /// Path relative to the OPF file.
  final String href;

  /// Inner markup of the XHTML body.
  final String body;

  final String? id;
  final String title;
  final bool inSpine;
}

/// A plain image resource referenced from an XHTML page.
class EpubFixtureImage {
  const EpubFixtureImage({
    required this.href,
    required this.bytes,
    this.mediaType = 'image/jpeg',
    this.id,
  });

  /// Path relative to the OPF file.
  final String href;
  final List<int> bytes;
  final String mediaType;
  final String? id;
}

/// An image item to declare as the EPUB cover.
class EpubFixtureCover {
  const EpubFixtureCover({
    required this.href,
    required this.bytes,
    this.mediaType = 'image/jpeg',
    this.id = 'cover-image',
    this.useMeta = false,
    this.declared = true,
  });

  /// Path relative to the OPF file.
  final String href;
  final List<int> bytes;
  final String mediaType;
  final String id;

  /// Declares the cover with the EPUB2 `<meta name="cover">` tag.
  final bool useMeta;

  /// Emits `properties="cover-image"` (EPUB3). When false the image is a
  /// plain manifest item, exercising the filename fallback.
  final bool declared;
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _xhtml(String title, String body) {
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh" '
      'xmlns:xlink="http://www.w3.org/1999/xlink">\n'
      '<head><title>${_escapeXml(title)}</title></head>\n'
      '<body>$body</body>\n'
      '</html>';
}

/// Builds a minimal but valid EPUB zip in memory.
///
/// [toc] maps document hrefs (relative to the OPF file) to TOC titles.
/// By default an EPUB3 nav document is generated; set [useNcx] for EPUB2.
List<int> buildEpubBytes({
  String opfPath = 'OEBPS/content.opf',
  required List<EpubFixtureDoc> docs,
  Map<String, String> toc = const {},
  bool useNcx = false,
  bool includeNavInSpine = false,
  EpubFixtureCover? cover,
  List<EpubFixtureImage> images = const [],
  String? renditionLayout,
  String mimetype = 'application/epub+zip',
}) {
  final opfDir = p.url.dirname(opfPath);
  final archive = Archive();
  archive.add(ArchiveFile.bytes('mimetype', utf8.encode(mimetype)));
  archive.add(ArchiveFile.bytes(
    'META-INF/container.xml',
    utf8.encode('<?xml version="1.0" encoding="utf-8"?>\n'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '<rootfiles><rootfile full-path="$opfPath" '
        'media-type="application/oebps-package+xml"/></rootfiles>\n'
        '</container>'),
  ));

  final ids = <EpubFixtureDoc, String>{};
  for (var i = 0; i < docs.length; i++) {
    ids[docs[i]] = docs[i].id ?? 'doc$i';
  }

  final manifest = StringBuffer();
  for (final doc in docs) {
    final fullPath = p.url.normalize(p.url.join(opfDir, doc.href));
    manifest.writeln(
      '<item id="${ids[doc]}" href="${_escapeXml(doc.href)}" '
      'media-type="application/xhtml+xml"/>',
    );
    archive.add(ArchiveFile.bytes(
      fullPath,
      utf8.encode(_xhtml(doc.title, doc.body)),
    ));
  }

  for (var i = 0; i < images.length; i++) {
    final image = images[i];
    manifest.writeln(
      '<item id="${image.id ?? 'img$i'}" href="${_escapeXml(image.href)}" '
      'media-type="${image.mediaType}"/>',
    );
    archive.add(ArchiveFile.bytes(
      p.url.normalize(p.url.join(opfDir, image.href)),
      image.bytes,
    ));
  }

  if (cover != null) {
    final property = cover.declared && !cover.useMeta
        ? ' properties="cover-image"'
        : '';
    manifest.writeln(
      '<item id="${cover.id}" href="${_escapeXml(cover.href)}" '
      'media-type="${cover.mediaType}"$property/>',
    );
    archive.add(ArchiveFile.bytes(
      p.url.normalize(p.url.join(opfDir, cover.href)),
      cover.bytes,
    ));
  }

  final navHref = useNcx ? 'toc.ncx' : 'nav.xhtml';
  final navId = useNcx ? 'ncx' : 'nav';
  if (useNcx) {
    manifest.writeln(
      '<item id="$navId" href="$navHref" '
      'media-type="application/x-dtbncx+xml"/>',
    );
    final navPoints = StringBuffer();
    var order = 1;
    toc.forEach((href, title) {
      navPoints.writeln(
        '<navPoint id="navPoint-$order" playOrder="$order">'
        '<navLabel><text>${_escapeXml(title)}</text></navLabel>'
        '<content src="${_escapeXml(href)}"/>'
        '</navPoint>',
      );
      order++;
    });
    archive.add(ArchiveFile.bytes(
      p.url.normalize(p.url.join(opfDir, navHref)),
      utf8.encode('<?xml version="1.0" encoding="utf-8"?>\n'
          '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
          '<head><meta name="dtb:uid" content="fixture"/></head>\n'
          '<docTitle><text>Fixture</text></docTitle>\n'
          '<navMap>$navPoints</navMap>\n'
          '</ncx>'),
    ));
  } else {
    manifest.writeln(
      '<item id="$navId" href="$navHref" '
      'media-type="application/xhtml+xml" properties="nav"/>',
    );
    final links = StringBuffer();
    toc.forEach((href, title) {
      links.writeln(
        '<li><a href="${_escapeXml(href)}">${_escapeXml(title)}</a></li>',
      );
    });
    archive.add(ArchiveFile.bytes(
      p.url.normalize(p.url.join(opfDir, navHref)),
      utf8.encode(_xhtml(
        '目录',
        '<nav epub:type="toc" '
            'xmlns:epub="http://www.idpf.org/2007/ops"><ol>$links</ol></nav>',
      )),
    ));
  }

  final itemRefs = StringBuffer();
  if (includeNavInSpine) {
    itemRefs.writeln('<itemref idref="$navId"/>');
  }
  for (final doc in docs) {
    if (doc.inSpine) {
      itemRefs.writeln('<itemref idref="${ids[doc]}"/>');
    }
  }

  final opf = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bookid">\n'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
      '<dc:identifier id="bookid">fixture</dc:identifier>\n'
      '<dc:title>Fixture Book</dc:title>\n'
      '<dc:creator>Fixture Author</dc:creator>\n'
      '<dc:language>zh</dc:language>\n'
      '${cover != null && cover.useMeta ? '<meta name="cover" content="${cover.id}"/>' : ''}'
      '${renditionLayout == null ? '' : '<meta property="rendition:layout">$renditionLayout</meta>'}'
      '</metadata>\n'
      '<manifest>\n$manifest</manifest>\n'
      '<spine${useNcx ? ' toc="$navId"' : ''}>\n$itemRefs</spine>\n'
      '</package>';
  archive.add(ArchiveFile.bytes(opfPath, utf8.encode(opf)));

  return ZipEncoder().encode(archive);
}
