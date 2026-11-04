import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Raised when an EPUB cannot be read or contains no readable body text.
class EpubParseException implements Exception {
  EpubParseException(this.message);

  final String message;

  @override
  String toString() => 'EpubParseException: $message';
}

/// A chapter extracted from an EPUB, with offsets relative to the whole book.
class EpubBookChapter {
  const EpubBookChapter({
    required this.title,
    required this.startOffset,
    required this.endOffset,
    required this.contentText,
    this.level = 1,
  });

  final String title;
  final int startOffset;
  final int endOffset;
  final String contentText;

  /// 1 for a part/chapter, 2 for a section nested inside it.
  final int level;
}

class EpubCover {
  const EpubCover({required this.bytes, required this.extension});

  final List<int> bytes;

  /// Lowercase file extension such as `jpg` or `png`.
  final String extension;
}

class EpubDocument {
  const EpubDocument({
    required this.chapters,
    this.cover,
    this.fixedLayout = false,
  });

  final List<EpubBookChapter> chapters;
  final EpubCover? cover;

  /// True for pre-paginated/comic packages whose pages are images.
  final bool fixedLayout;
}

/// One raster page of a comic EPUB, already decoded from the archive.
class EpubComicPage {
  const EpubComicPage({
    required this.bytes,
    required this.extension,
    this.title,
  });

  final List<int> bytes;
  final String extension;
  final String? title;
}

class EpubComicDocument {
  const EpubComicDocument({required this.pages});

  final List<EpubComicPage> pages;
}

/// Parses an EPUB into plain-text chapters in spine order.
///
/// The returned chapters have contiguous [EpubBookChapter.startOffset] and
/// [EpubBookChapter.endOffset] values over the concatenated extracted text,
/// matching the offsets produced by TXT imports.
EpubDocument parseEpubDocument(List<int> bytes) {
  if (bytes.isEmpty) {
    throw EpubParseException('文件内容为空');
  }
  try {
    return _EpubParser(bytes).parse();
  } on EpubParseException {
    rethrow;
  } catch (error) {
    throw EpubParseException('无法解析 EPUB：$error');
  }
}

/// Reads only the embedded cover image, without extracting body text.
EpubCover? parseEpubCover(List<int> bytes) {
  if (bytes.isEmpty) return null;
  try {
    return _EpubParser(bytes).parseCover();
  } catch (_) {
    return null;
  }
}

/// Reads the raster pages of a comic/fixed-layout EPUB in spine order.
///
/// Returns null when the archive cannot be read or has no images, so callers
/// can treat it as a plain text import.
EpubComicDocument? parseEpubComic(List<int> bytes) {
  if (bytes.isEmpty) return null;
  try {
    return _EpubParser(bytes).parseComic();
  } catch (_) {
    return null;
  }
}

class _TocEntry {
  const _TocEntry({
    required this.title,
    required this.path,
    required this.fragment,
    required this.level,
  });

  final String title;
  final String path;
  final String? fragment;
  final int level;
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.path,
    required this.mediaType,
    required this.properties,
  });

  final String id;
  final String path;
  final String mediaType;
  final String properties;
}

class _EpubParser {
  _EpubParser(this.bytes);

  final List<int> bytes;
  late final Map<String, ArchiveFile> _files;

  EpubDocument parse() {
    final package = _readPackage();
    final opf = package.opf;
    final manifest = package.manifest;

    final spine = _firstWhereOrNull(
      opf.findAllElements('spine', namespaceUri: '*'),
      (_) => true,
    );
    if (spine == null) {
      throw EpubParseException('缺少 spine');
    }

    final navPath = _firstWhereOrNull(
      manifest.values,
      (item) => item.properties
          .split(RegExp(r'\s+'))
          .contains('nav'),
    )?.path;
    final tocEntries = _readTocEntries(opf, spine, manifest);
    final entriesByPath = <String, List<_TocEntry>>{};
    for (final entry in tocEntries) {
      entriesByPath.putIfAbsent(entry.path, () => []).add(entry);
    }

    final chapters = <EpubBookChapter>[];
    var cursor = 0;
    for (final itemref in spine.findAllElements('itemref', namespaceUri: '*')) {
      final idref = itemref.getAttribute('idref');
      if (idref == null) continue;
      final item = manifest[idref];
      if (item == null) continue;
      if (item.path == navPath) continue;
      if (item.mediaType.isNotEmpty &&
          !item.mediaType.contains('xhtml') &&
          !item.mediaType.contains('html')) {
        continue;
      }

      final itemEntries = entriesByPath[item.path] ?? const <_TocEntry>[];
      final fragmentIds = <String>{
        for (final entry in itemEntries)
          if (entry.fragment != null) entry.fragment!,
      };
      final extracted = _extractPlainTextWithAnchors(item.path, fragmentIds);
      final text = extracted.text;
      if (text.isEmpty) continue;

      final segments = _chapterSegments(text, itemEntries, extracted.anchors);
      if (segments.isEmpty) {
        final title = itemEntries.isEmpty
            ? _fallbackTitle(item.path, chapters.length + 1)
            : itemEntries.first.title;
        chapters.add(EpubBookChapter(
          title: title,
          startOffset: cursor,
          endOffset: cursor + text.length,
          contentText: text,
        ));
        cursor += text.length;
        continue;
      }

      for (final segment in segments) {
        chapters.add(EpubBookChapter(
          title: segment.title,
          level: segment.level,
          startOffset: cursor,
          endOffset: cursor + segment.text.length,
          contentText: segment.text,
        ));
        cursor += segment.text.length;
      }
    }

    return EpubDocument(
      chapters: chapters,
      cover: _readCover(opf, manifest),
      fixedLayout: _readFixedLayout(opf),
    );
  }

  EpubCover? parseCover() {
    final package = _readPackage();
    return _readCover(package.opf, package.manifest);
  }

  EpubComicDocument? parseComic() {
    final package = _readPackage();
    final opf = package.opf;
    final manifest = package.manifest;
    final spine = _firstWhereOrNull(
      opf.findAllElements('spine', namespaceUri: '*'),
      (_) => true,
    );
    if (spine == null) return null;

    final navPath = _firstWhereOrNull(
      manifest.values,
      (item) => item.properties
          .split(RegExp(r'\s+'))
          .contains('nav'),
    )?.path;
    final titles = _readTocTitles(opf, spine, manifest);

    final pages = <EpubComicPage>[];
    for (final itemref in spine.findAllElements('itemref', namespaceUri: '*')) {
      final idref = itemref.getAttribute('idref');
      if (idref == null) continue;
      final item = manifest[idref];
      if (item == null) continue;
      if (item.path == navPath) continue;
      if (item.mediaType.isNotEmpty &&
          !item.mediaType.contains('xhtml') &&
          !item.mediaType.contains('html')) {
        continue;
      }

      final images = _extractPageImages(item.path);
      for (var i = 0; i < images.length; i++) {
        pages.add(EpubComicPage(
          bytes: images[i].bytes,
          extension: images[i].extension,
          title: i == 0 ? titles[item.path] : null,
        ));
      }
    }

    if (pages.isEmpty) return null;
    return EpubComicDocument(pages: List.unmodifiable(pages));
  }

  bool _readFixedLayout(XmlDocument opf) {
    for (final meta in opf.findAllElements('meta', namespaceUri: '*')) {
      final property =
          (meta.getAttribute('property') ?? '').trim().toLowerCase();
      if (property == 'rendition:layout') {
        final value = meta.innerText.trim().toLowerCase();
        if (value == 'pre-paginated' || value == 'prepaginated') return true;
      }
      final name = (meta.getAttribute('name') ?? '').trim().toLowerCase();
      final content = (meta.getAttribute('content') ?? '').trim().toLowerCase();
      if (name == 'book-type' && content.contains('comic')) return true;
      if (name == 'fixed-layout' && content == 'true') return true;
    }
    return false;
  }

  ({XmlDocument opf, Map<String, _ManifestItem> manifest}) _readPackage() {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw EpubParseException('不是有效的 EPUB 压缩包');
    }

    _files = {};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      _files[_normalizePath(file.name)] = file;
    }

    final container = _parseXml(_readText('META-INF/container.xml'));
    final rootfile = _firstWhereOrNull(
      container.findAllElements('rootfile', namespaceUri: '*'),
      (element) =>
          (element.getAttribute('media-type') ?? '')
              .toLowerCase()
              .contains('oebps-package'),
    ) ??
        _firstWhereOrNull(
          container.findAllElements('rootfile', namespaceUri: '*'),
          (_) => true,
        );
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null || opfPath.trim().isEmpty) {
      throw EpubParseException('缺少 OPF 文件');
    }

    final opf = _parseXml(_readText(opfPath));
    final manifest = <String, _ManifestItem>{};
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null || href.trim().isEmpty) continue;
      manifest[id] = _ManifestItem(
        id: id,
        path: _resolvePath(opfPath, href),
        mediaType: (item.getAttribute('media-type') ?? '').toLowerCase(),
        properties: item.getAttribute('properties') ?? '',
      );
    }

    return (opf: opf, manifest: manifest);
  }

  EpubCover? _readCover(
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
  ) {
    final item = _coverItem(opf, manifest);
    if (item == null) return null;
    final file = _files[_normalizePath(item.path)];
    if (file == null) return null;
    final data = file.content;
    if (data.isEmpty) return null;
    final extension =
        p.url.extension(item.path).replaceFirst('.', '').toLowerCase();
    return EpubCover(
      bytes: data,
      extension: extension == 'jpeg' ? 'jpg' : extension,
    );
  }

  _ManifestItem? _coverItem(
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
  ) {
    for (final item in manifest.values) {
      if (!_isRasterImage(item)) continue;
      if (item.properties.split(RegExp(r'\s+')).contains('cover-image')) {
        return item;
      }
    }

    final meta = _firstWhereOrNull(
      opf.findAllElements('meta', namespaceUri: '*'),
      (element) =>
          (element.getAttribute('name') ?? '').toLowerCase() == 'cover',
    );
    final metaId = meta?.getAttribute('content')?.trim();
    if (metaId != null && metaId.isNotEmpty) {
      final item = manifest[metaId];
      if (item != null && _isRasterImage(item)) return item;
    }

    return _firstWhereOrNull(manifest.values, (item) {
      if (!_isRasterImage(item)) return false;
      final name =
          p.url.basenameWithoutExtension(item.path).toLowerCase();
      return item.id.toLowerCase().contains('cover') ||
          name.contains('cover');
    });
  }

  bool _isRasterImage(_ManifestItem item) {
    if (!item.mediaType.startsWith('image/')) return false;
    if (item.mediaType.contains('svg')) return false;
    final extension =
        p.url.extension(item.path).replaceFirst('.', '').toLowerCase();
    return _rasterExtensions.contains(extension);
  }

  Map<String, String> _readTocTitles(
    XmlDocument opf,
    XmlElement spine,
    Map<String, _ManifestItem> manifest,
  ) {
    final titles = <String, String>{};
    for (final entry in _readTocEntries(opf, spine, manifest)) {
      titles.putIfAbsent(entry.path, () => entry.title);
    }
    return titles;
  }

  List<_TocEntry> _readTocEntries(
    XmlDocument opf,
    XmlElement spine,
    Map<String, _ManifestItem> manifest,
  ) {
    final navItem = _firstWhereOrNull(
      manifest.values,
      (item) => item.properties
          .split(RegExp(r'\s+'))
          .contains('nav'),
    );
    if (navItem != null) {
      final entries = _readNavEntries(navItem);
      if (entries.isNotEmpty) return entries;
    }

    final spineToc = spine.getAttribute('toc');
    final ncxItem = (spineToc != null ? manifest[spineToc] : null) ??
        _firstWhereOrNull(
          manifest.values,
          (item) => item.mediaType.contains('dtbncx'),
        );
    if (ncxItem != null) {
      final entries = _readNcxEntries(ncxItem);
      if (entries.isNotEmpty) return entries;
    }
    return const [];
  }

  List<_TocEntry> _readNavEntries(_ManifestItem navItem) {
    try {
      final document = _parseXml(_readText(navItem.path));
      final navElements =
          document.findAllElements('nav', namespaceUri: '*').toList();
      XmlElement? tocNav;
      for (final nav in navElements) {
        final isToc = nav.attributes.any((attribute) {
          if (attribute.name.local.toLowerCase() != 'type') return false;
          return attribute.value
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .contains('toc');
        });
        if (isToc) {
          tocNav = nav;
          break;
        }
      }
      tocNav ??= navElements.isEmpty ? null : navElements.first;
      if (tocNav == null) return const [];

      final rootList = _firstWhereOrNull(
        tocNav.findAllElements('ol', namespaceUri: '*'),
        (_) => true,
      );
      if (rootList == null) return const [];

      final entries = <_TocEntry>[];
      void walk(XmlElement list, int depth) {
        for (final item in list.children.whereType<XmlElement>()) {
          if (item.name.local.toLowerCase() != 'li') continue;
          final anchor = _firstWhereOrNull(
            item.children.whereType<XmlElement>(),
            (child) => child.name.local.toLowerCase() == 'a',
          );
          if (anchor != null) {
            final href = anchor.getAttribute('href');
            final title = _normalizeInline(anchor.innerText);
            if (href != null && href.trim().isNotEmpty && title.isNotEmpty) {
              final target = _resolveTarget(navItem.path, href);
              entries.add(_TocEntry(
                title: title,
                path: target.path,
                fragment: target.fragment,
                level: depth + 1,
              ));
            }
          }
          final nested = _firstWhereOrNull(
            item.children.whereType<XmlElement>(),
            (child) => child.name.local.toLowerCase() == 'ol',
          );
          if (nested != null) walk(nested, depth + 1);
        }
      }

      walk(rootList, 0);
      return entries;
    } catch (_) {
      return const [];
    }
  }

  List<_TocEntry> _readNcxEntries(_ManifestItem ncxItem) {
    try {
      final document = _parseXml(_readText(ncxItem.path));
      final entries = <_TocEntry>[];
      final navMap = _firstWhereOrNull(
        document.findAllElements('navMap', namespaceUri: '*'),
        (_) => true,
      );
      if (navMap == null) return const [];

      void walk(XmlElement parent, int depth) {
        for (final navPoint in parent.children.whereType<XmlElement>()) {
          if (navPoint.name.local.toLowerCase() != 'navpoint') continue;
          final label = _firstWhereOrNull(
            navPoint.findAllElements('navLabel', namespaceUri: '*'),
            (_) => true,
          );
          final content = _firstWhereOrNull(
            navPoint.findAllElements('content', namespaceUri: '*'),
            (_) => true,
          );
          final src = content?.getAttribute('src');
          final title = label == null ? '' : _normalizeInline(label.innerText);
          if (src != null && src.trim().isNotEmpty && title.isNotEmpty) {
            final target = _resolveTarget(ncxItem.path, src);
            entries.add(_TocEntry(
              title: title,
              path: target.path,
              fragment: target.fragment,
              level: depth + 1,
            ));
          }
          walk(navPoint, depth + 1);
        }
      }

      walk(navMap, 0);
      return entries;
    } catch (_) {
      return const [];
    }
  }

  List<({String title, int level, String text})> _chapterSegments(
    String text,
    List<_TocEntry> entries,
    Map<String, int> anchors,
  ) {
    if (entries.isEmpty) return const [];

    final starts = <({int offset, _TocEntry entry})>[];
    for (final entry in entries) {
      final fragment = entry.fragment;
      final offset = fragment == null ? 0 : anchors[fragment];
      if (offset == null || offset < 0 || offset >= text.length) continue;
      starts.add((offset: offset, entry: entry));
    }
    if (starts.isEmpty) return const [];
    starts.sort((a, b) => a.offset.compareTo(b.offset));

    final segments = <({String title, int level, String text})>[];
    final firstOffset = starts.first.offset;
    if (firstOffset > 0) {
      segments.add((
        title: '前言',
        level: 1,
        text: text.substring(0, firstOffset).trim(),
      ));
    }
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i].offset;
      final end = i + 1 < starts.length ? starts[i + 1].offset : text.length;
      if (end <= start) continue;
      segments.add((
        title: starts[i].entry.title,
        level: starts[i].entry.level,
        text: text.substring(start, end).trim(),
      ));
    }
    return segments;
  }

  List<({List<int> bytes, String extension})> _extractPageImages(
    String path,
  ) {
    try {
      final document = _parseXml(_readText(path));
      final body = _firstWhereOrNull(
        document.findAllElements('body', namespaceUri: '*'),
        (_) => true,
      );
      final container = body ?? document;
      final images = <({List<int> bytes, String extension})>[];
      for (final element in container.descendants.whereType<XmlElement>()) {
        final tag = element.name.local.toLowerCase();
        if (tag != 'img' && tag != 'image') continue;
        final href = _hrefOf(element);
        if (href == null || href.trim().isEmpty) continue;

        final resolved = _resolvePath(path, href);
        final file = _files[_normalizePath(resolved)];
        if (file == null) continue;
        final extension =
            p.url.extension(resolved).replaceFirst('.', '').toLowerCase();
        if (!_rasterExtensions.contains(extension)) continue;
        final data = file.content;
        if (data.isEmpty) continue;
        images.add((
          bytes: data,
          extension: extension == 'jpeg' ? 'jpg' : extension,
        ));
      }
      return images;
    } catch (_) {
      return const [];
    }
  }

  String? _hrefOf(XmlElement element) {
    final src = element.getAttribute('src');
    if (src != null) return src;
    for (final attribute in element.attributes) {
      if (attribute.name.local.toLowerCase() == 'href') {
        return attribute.value;
      }
    }
    return null;
  }

  ({String text, Map<String, int> anchors}) _extractPlainTextWithAnchors(
    String path,
    Set<String> anchorIds,
  ) {
    final source = _readText(path);
    try {
      final document = _parseXml(source);
      final body = _firstWhereOrNull(
        document.findAllElements('body', namespaceUri: '*'),
        (_) => true,
      );
      final container = body ?? document;
      final buffer = StringBuffer();
      final anchorOrder = <String>[];
      for (final child in container.children) {
        _collectText(
          child,
          buffer,
          anchorIds: anchorIds,
          anchorOrder: anchorOrder,
        );
      }
      return _normalizeTextTrackingAnchors(buffer.toString(), anchorOrder);
    } catch (_) {
      // Tolerate slightly malformed XHTML instead of losing the whole book.
      return (
        text: _normalizePlainText(_stripTagsFallback(source)),
        anchors: const <String, int>{},
      );
    }
  }

  void _collectText(
    XmlNode node,
    StringBuffer buffer, {
    Set<String> anchorIds = const {},
    List<String>? anchorOrder,
  }) {
    if (node is XmlText) {
      buffer.write(node.value);
      return;
    }
    if (node is! XmlElement) return;

    final tag = node.name.local.toLowerCase();
    if (_ignoredTags.contains(tag)) return;
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }

    final id = node.getAttribute('id');
    if (anchorOrder != null && id != null && anchorIds.contains(id)) {
      buffer.writeCharCode(0x0001);
      anchorOrder.add(id);
    }

    final isBlock = _blockTags.contains(tag);
    if (isBlock) buffer.write('\n');
    for (final child in node.children) {
      _collectText(
        child,
        buffer,
        anchorIds: anchorIds,
        anchorOrder: anchorOrder,
      );
    }
    if (isBlock) buffer.write('\n');
  }

  ({String text, Map<String, int> anchors}) _normalizeTextTrackingAnchors(
    String raw,
    List<String> anchorOrder,
  ) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final buffer = StringBuffer();
    final anchors = <String, int>{};
    var anchorIndex = 0;
    var written = 0;
    var hasLine = false;
    for (final line in normalized.split('\n')) {
      final collapsed = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (collapsed.isEmpty) continue;
      if (hasLine) {
        buffer.write('\n');
        written += 1;
      }
      for (var i = 0; i < collapsed.length; i++) {
        final code = collapsed.codeUnitAt(i);
        if (code == 0x0001) {
          if (anchorIndex < anchorOrder.length) {
            anchors.putIfAbsent(anchorOrder[anchorIndex], () => written);
          }
          anchorIndex++;
          continue;
        }
        buffer.writeCharCode(code);
        written += 1;
      }
      hasLine = true;
    }
    return (text: buffer.toString(), anchors: anchors);
  }

  String _stripTagsFallback(String source) {
    var text = source;
    for (final tag in const ['script', 'style', 'head', 'title']) {
      text = text.replaceAll(
        RegExp('<$tag\\b[^>]*>.*?</$tag>',
            caseSensitive: false, dotAll: true),
        ' ',
      );
    }
    text = text.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(
      RegExp(
        r'</(?:p|div|h[1-6]|li|tr|section|article|blockquote|figcaption)>',
        caseSensitive: false,
      ),
      '\n',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return const XmlDefaultEntityMapping.html5().decode(text);
  }

  String _readText(String path) {
    final normalized = _normalizePath(path);
    final file = _files[normalized];
    if (file == null) {
      throw EpubParseException('缺少文件 $normalized');
    }
    var text = utf8.decode(file.content, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    return text;
  }

  XmlDocument _parseXml(String input) {
    return XmlDocument.parse(
      input,
      entityMapping: const XmlDefaultEntityMapping.html5(),
    );
  }

  String _resolvePath(String basePath, String href) {
    var target = href.trim();
    final fragment = target.indexOf('#');
    if (fragment >= 0) target = target.substring(0, fragment);
    final query = target.indexOf('?');
    if (query >= 0) target = target.substring(0, query);
    if (target.isEmpty) return _normalizePath(basePath);
    try {
      target = Uri.decodeFull(target);
    } catch (_) {
      // Keep the raw value when it is not valid percent-encoding.
    }
    final directory = p.url.dirname(basePath);
    return _normalizePath(
      p.url.join(directory == '.' ? '' : directory, target),
    );
  }

  ({String path, String? fragment}) _resolveTarget(
    String basePath,
    String href,
  ) {
    var target = href.trim();
    String? fragment;
    final hash = target.indexOf('#');
    if (hash >= 0) {
      final rawFragment = target.substring(hash + 1).trim();
      fragment = rawFragment.isEmpty ? null : rawFragment;
      target = target.substring(0, hash);
    }
    return (path: _resolvePath(basePath, target), fragment: fragment);
  }

  String _normalizePath(String path) {
    var normalized = p.url.normalize(path.replaceAll('\\', '/'));
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  String _fallbackTitle(String path, int ordinal) {
    final name = p.url.basenameWithoutExtension(path).trim();
    if (name.isNotEmpty) return name;
    return '第$ordinal节';
  }
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

String _normalizeInline(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalizePlainText(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = <String>[];
  for (final line in normalized.split('\n')) {
    final collapsed = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isNotEmpty) lines.add(collapsed);
  }
  return lines.join('\n');
}

const Set<String> _rasterExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
};

const Set<String> _ignoredTags = {
  'script',
  'style',
  'head',
  'title',
  'svg',
  'rt',
  'rp',
  'nav',
};

const Set<String> _blockTags = {
  'address',
  'article',
  'aside',
  'blockquote',
  'div',
  'dl',
  'dt',
  'dd',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tr',
  'ul',
};
