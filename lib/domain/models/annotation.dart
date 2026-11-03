enum AnnotationType {
  bookmark,
  highlight,
  note;

  static AnnotationType fromName(String name) {
    return AnnotationType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => AnnotationType.bookmark,
    );
  }
}

class Annotation {
  const Annotation({
    required this.id,
    required this.bookId,
    required this.type,
    required this.anchorStart,
    required this.createdAt,
    required this.updatedAt,
    this.chapterId,
    this.anchorEnd,
    this.selectedText = '',
    this.color,
    this.noteText = '',
    this.anchorVersion = 1,
  });

  final String id;
  final String bookId;
  final String? chapterId;
  final AnnotationType type;
  final int anchorStart;
  final int? anchorEnd;
  final String selectedText;
  final String? color;
  final String noteText;
  final int anchorVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
}
