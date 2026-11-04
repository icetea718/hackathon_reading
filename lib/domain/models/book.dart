enum BookFormat {
  epub,
  txt,
  pdf;

  String get extension => name;

  String get label => switch (this) {
        BookFormat.epub => 'EPUB',
        BookFormat.txt => 'TXT',
        BookFormat.pdf => 'PDF',
      };

  static BookFormat? fromExtension(String pathOrName) {
    final dot = pathOrName.lastIndexOf('.');
    if (dot == -1 || dot == pathOrName.length - 1) return null;
    final ext = pathOrName.substring(dot + 1).toLowerCase();
    for (final format in BookFormat.values) {
      if (format.name == ext) return format;
    }
    return null;
  }
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.sourcePath,
    required this.addedAt,
    this.coverPath,
    this.contentHash,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String author;
  final BookFormat format;
  final String sourcePath;
  final String? coverPath;
  final String? contentHash;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
}
