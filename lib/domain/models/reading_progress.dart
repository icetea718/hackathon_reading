class ReadingAnchor {
  const ReadingAnchor({required this.charOffset, this.page});

  const ReadingAnchor.page(int page) : this(charOffset: 0, page: page);

  final int charOffset;
  final int? page;

  Map<String, dynamic> toJson() => {
        'charOffset': charOffset,
        if (page != null) 'page': page,
      };

  factory ReadingAnchor.fromJson(Map<String, dynamic> json) {
    return ReadingAnchor(
      charOffset: json['charOffset'] as int,
      page: json['page'] as int?,
    );
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
