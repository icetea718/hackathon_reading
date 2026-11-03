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
  });

  final String title;
  final int startOffset;
  final int endOffset;
  final String contentText;
}

class EpubDocument {
  const EpubDocument({required this.chapters});

  final List<EpubBookChapter> chapters;
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
    final titles = _readTocTitles(opf, spine, manifest);

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

      final text = _extractPlainText(item.path);
      if (text.isEmpty) continue;

      final title = titles[item.path] ??
          _fallbackTitle(item.path, chapters.length + 1);
      chapters.add(EpubBookChapter(
        title: title,
        startOffset: cursor,
        endOffset: cursor + text.length,
        contentText: text,
      ));
      cursor += text.length;
    }

    if (chapters.isEmpty) {
      throw EpubParseException('没有可读正文');
    }
    return EpubDocument(chapters: chapters);
  }

  Map<String, String> _readTocTitles(
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
      final titles = _readNavTitles(navItem);
      if (titles.isNotEmpty) return titles;
    }

    final spineToc = spine.getAttribute('toc');
    final ncxItem = (spineToc != null ? manifest[spineToc] : null) ??
        _firstWhereOrNull(
          manifest.values,
          (item) => item.mediaType.contains('dtbncx'),
        );
    if (ncxItem != null) {
      final titles = _readNcxTitles(ncxItem);
      if (titles.isNotEmpty) return titles;
    }
    return const {};
  }

  Map<String, String> _readNavTitles(_ManifestItem navItem) {
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
      if (tocNav == null) return const {};

      final titles = <String, String>{};
      for (final anchor in tocNav.findAllElements('a', namespaceUri: '*')) {
        final href = anchor.getAttribute('href');
        if (href == null || href.trim().isEmpty) continue;
        final title = _normalizeInline(anchor.innerText);
        if (title.isEmpty) continue;
        titles.putIfAbsent(_resolvePath(navItem.path, href), () => title);
      }
      return titles;
    } catch (_) {
      return const {};
    }
  }

  Map<String, String> _readNcxTitles(_ManifestItem ncxItem) {
    try {
      final document = _parseXml(_readText(ncxItem.path));
      final titles = <String, String>{};
      for (final navPoint
          in document.findAllElements('navPoint', namespaceUri: '*')) {
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
        if (src == null || src.trim().isEmpty || title.isEmpty) continue;
        titles.putIfAbsent(_resolvePath(ncxItem.path, src), () => title);
      }
      return titles;
    } catch (_) {
      return const {};
    }
  }

  String _extractPlainText(String path) {
    final source = _readText(path);
    try {
      final document = _parseXml(source);
      final body = _firstWhereOrNull(
        document.findAllElements('body', namespaceUri: '*'),
        (_) => true,
      );
      final container = body ?? document;
      final buffer = StringBuffer();
      for (final child in container.children) {
        _collectText(child, buffer);
      }
      return _normalizePlainText(buffer.toString());
    } catch (_) {
      // Tolerate slightly malformed XHTML instead of losing the whole book.
      return _normalizePlainText(_stripTagsFallback(source));
    }
  }

  void _collectText(XmlNode node, StringBuffer buffer) {
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

    final isBlock = _blockTags.contains(tag);
    if (isBlock) buffer.write('\n');
    for (final child in node.children) {
      _collectText(child, buffer);
    }
    if (isBlock) buffer.write('\n');
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
