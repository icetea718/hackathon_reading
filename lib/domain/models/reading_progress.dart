class ReadingAnchor {
  const ReadingAnchor({required this.charOffset});

  final int charOffset;

  Map<String, dynamic> toJson() => {'charOffset': charOffset};

  factory ReadingAnchor.fromJson(Map<String, dynamic> json) {
    return ReadingAnchor(charOffset: json['charOffset'] as int);
  }
}

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.anchor,
    required this.percent,
    required this.updatedAt,
  });

  final String bookId;
  final ReadingAnchor anchor;
  final double percent;
  final DateTime updatedAt;
}
