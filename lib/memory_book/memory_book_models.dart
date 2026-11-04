class MemoryPage {
  const MemoryPage({
    required this.id,
    required this.fileName,
    required this.imagePath,
    required this.createdAt,
    this.excerpt = '',
    this.medium = '',
  });

  final String id;
  final String fileName;
  final String imagePath;
  final DateTime createdAt;
  final String excerpt;
  final String medium;

  String get dateLabel =>
      '${createdAt.year}年${createdAt.month}月${createdAt.day}日';

  Map<String, Object?> toJson() => {
        'id': id,
        'fileName': fileName,
        'createdAt': createdAt.toIso8601String(),
        'excerpt': excerpt,
        'medium': medium,
      };
}

class MemoryBook {
  MemoryBook({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required List<MemoryPage> pages,
  }) : pages = List.unmodifiable(pages);

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MemoryPage> pages;

  int get pageCount => pages.length;

  String? get coverPath => pages.isEmpty ? null : pages.first.imagePath;

  String get dateLabel =>
      '${createdAt.year}年${createdAt.month}月${createdAt.day}日';

  MemoryBook copyWith({
    String? title,
    DateTime? updatedAt,
    List<MemoryPage>? pages,
  }) {
    return MemoryBook(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pages: pages ?? this.pages,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pages': pages.map((page) => page.toJson()).toList(),
      };
}

class MemoryBookException implements Exception {
  MemoryBookException(this.message);

  final String message;

  @override
  String toString() => message;
}
