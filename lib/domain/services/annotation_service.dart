import 'package:uuid/uuid.dart';

import '../../data/repositories/annotation_repository.dart';
import '../models/annotation.dart';

class AnnotationService {
  AnnotationService(this._repository, {String Function()? newId})
      : _newId = newId ?? const Uuid().v4;

  final AnnotationRepository _repository;
  final String Function() _newId;

  Future<Annotation> addHighlight({
    required String bookId,
    required String chapterId,
    required int anchorStart,
    required int anchorEnd,
    required String selectedText,
    required String color,
  }) {
    return _create(
      bookId: bookId,
      chapterId: chapterId,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      selectedText: selectedText,
      type: AnnotationType.highlight,
      color: color,
    );
  }

  Future<Annotation> addNote({
    required String bookId,
    required String chapterId,
    required int anchorStart,
    required int anchorEnd,
    required String selectedText,
    required String noteText,
    String color = 'yellow',
  }) {
    return _create(
      bookId: bookId,
      chapterId: chapterId,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      selectedText: selectedText,
      type: AnnotationType.note,
      color: color,
      noteText: noteText,
    );
  }

  Future<List<Annotation>> getHighlightsAndNotes(String bookId) async {
    final annotations = await _repository.getForBook(bookId);
    return annotations
        .where((annotation) =>
            annotation.type == AnnotationType.highlight ||
            annotation.type == AnnotationType.note)
        .toList();
  }

  Future<void> delete(String id) => _repository.delete(id);

  Future<Annotation> _create({
    required String bookId,
    required String chapterId,
    required int anchorStart,
    required int anchorEnd,
    required String selectedText,
    required AnnotationType type,
    required String color,
    String noteText = '',
  }) async {
    if (anchorEnd <= anchorStart) {
      throw ArgumentError.value(
        anchorEnd,
        'anchorEnd',
        'must be greater than anchorStart',
      );
    }
    final now = DateTime.now();
    final annotation = Annotation(
      id: _newId(),
      bookId: bookId,
      chapterId: chapterId,
      type: type,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      selectedText: selectedText,
      color: color,
      noteText: noteText,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.upsert(annotation);
    return annotation;
  }
}
