enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final ChatRole role;
  final String content;
}

class ReadingContext {
  const ReadingContext({
    required this.bookTitle,
    this.author = '',
    this.chapterTitle = '',
    this.chapterText = '',
    this.selectedText = '',
  });

  final String bookTitle;
  final String author;
  final String chapterTitle;
  final String chapterText;
  final String selectedText;
}
