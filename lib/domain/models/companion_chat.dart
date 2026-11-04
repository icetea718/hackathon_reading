enum CompanionRole {
  user,
  assistant;

  static CompanionRole fromName(String name) {
    return CompanionRole.values.firstWhere(
      (role) => role.name == name,
      orElse: () => CompanionRole.user,
    );
  }
}

class CompanionThread {
  const CompanionThread({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
  });

  final String id;
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  CompanionThread copyWith({
    String? title,
    DateTime? updatedAt,
    int? messageCount,
  }) {
    return CompanionThread(
      id: id,
      bookId: bookId,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }
}

class CompanionMessage {
  const CompanionMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    required this.seq,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final CompanionRole role;
  final String content;
  final int seq;
  final DateTime createdAt;
}

String companionThreadTitle(String text) {
  final trimmed = text.trim();
  final runes = trimmed.runes.toList();
  if (runes.length <= 16) return trimmed;
  return '${String.fromCharCodes(runes.take(16))}…';
}
