import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coread/data/db/app_database.dart';
import 'package:coread/data/repositories/annotation_repository.dart';
import 'package:coread/domain/models/annotation.dart';
import 'package:coread/domain/services/annotation_service.dart';

void main() {
  late AppDatabase db;
  late AnnotationRepository repository;
  late AnnotationService service;

  setUp(() {
    var sequence = 0;
    db = AppDatabase(NativeDatabase.memory());
    repository = AnnotationRepository(db);
    service = AnnotationService(repository, newId: () => 'id-${sequence++}');
  });

  tearDown(() async {
    await db.close();
  });

  test('creates a highlight with its range, text and colour', () async {
    final highlight = await service.addHighlight(
      bookId: 'b1',
      chapterId: 'c1',
      anchorStart: 120,
      anchorEnd: 128,
      selectedText: '被高亮的文字',
      color: 'green',
    );

    expect(highlight.type, AnnotationType.highlight);
    expect(highlight.anchorStart, 120);
    expect(highlight.anchorEnd, 128);
    expect(highlight.selectedText, '被高亮的文字');
    expect(highlight.color, 'green');
    expect(highlight.chapterId, 'c1');

    final stored = await repository.getForBook('b1');
    expect(stored, hasLength(1));
    expect(stored.single.id, 'id-0');
  });

  test('creates a note with its text', () async {
    final note = await service.addNote(
      bookId: 'b1',
      chapterId: 'c1',
      anchorStart: 130,
      anchorEnd: 133,
      selectedText: '原文',
      noteText: '这里要再想想',
    );

    expect(note.type, AnnotationType.note);
    expect(note.noteText, '这里要再想想');
    expect((await repository.getForBook('b1')).single.noteText, '这里要再想想');
  });

  test('lists highlights and notes but not bookmarks', () async {
    await service.addHighlight(
      bookId: 'b1',
      chapterId: 'c1',
      anchorStart: 10,
      anchorEnd: 12,
      selectedText: '一',
      color: 'yellow',
    );
    await service.addNote(
      bookId: 'b1',
      chapterId: 'c1',
      anchorStart: 20,
      anchorEnd: 22,
      selectedText: '二',
      noteText: '备注',
    );
    final now = DateTime(2026, 1, 1);
    await repository.upsert(Annotation(
      id: 'bookmark',
      bookId: 'b1',
      type: AnnotationType.bookmark,
      anchorStart: 30,
      createdAt: now,
      updatedAt: now,
    ));

    final annotations = await service.getHighlightsAndNotes('b1');

    expect(annotations, hasLength(2));
    expect(
      annotations.map((annotation) => annotation.type),
      containsAll([AnnotationType.highlight, AnnotationType.note]),
    );
  });

  test('rejects ranges whose end is not after the start', () async {
    expect(
      () => service.addHighlight(
        bookId: 'b1',
        chapterId: 'c1',
        anchorStart: 10,
        anchorEnd: 10,
        selectedText: '',
        color: 'yellow',
      ),
      throwsArgumentError,
    );
    expect(await repository.getForBook('b1'), isEmpty);
  });

  test('deletes an annotation by id', () async {
    final highlight = await service.addHighlight(
      bookId: 'b1',
      chapterId: 'c1',
      anchorStart: 10,
      anchorEnd: 12,
      selectedText: '一',
      color: 'yellow',
    );

    await service.delete(highlight.id);

    expect(await repository.getForBook('b1'), isEmpty);
  });
}
