/// Raised when a translation cannot be produced; [message] is user facing.
class TranslationException implements Exception {
  const TranslationException(this.message);

  final String message;

  @override
  String toString() => message;
}
