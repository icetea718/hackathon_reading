import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/distill_artifact_repository.dart';
import 'package:hackathon_reading/data/repositories/distill_job_repository.dart';
import 'package:hackathon_reading/data/repositories/distill_unit_repository.dart';
import 'package:hackathon_reading/domain/models/distill.dart';

void main() {
  late AppDatabase db;
  late DistillJobRepository jobs;
  late DistillUnitRepository units;
  late DistillArtifactRepository artifacts;
  final now = DateTime.utc(2026, 11, 3, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    jobs = DistillJobRepository(db);
    units = DistillUnitRepository(db);
    artifacts = DistillArtifactRepository(db);
  });
  tearDown(() => db.close());

  DistillJob job({String status = 'running', int done = 0}) => DistillJob(
        id: 'job-1',
        bookId: 'book-1',
        contentHash: 'hash-1',
        status: DistillStatus.values.byName(status),
        stage: DistillStage.map,
        pipelineVersion: 1,
        totalUnits: 3,
        doneUnits: done,
        createdAt: now,
        updatedAt: now,
      );

  DistillUnit unit(String key, {String status = 'done'}) => DistillUnit(
        id: 'unit-$key',
        jobId: 'job-1',
        unitKey: key,
        kind: 'segment',
        status: status,
        resultJson: '{"summary":"x"}',
        attempts: 1,
        updatedAt: now,
      );

  DistillArtifact artifact(
    String key, {
    DistillArtifactKind kind = DistillArtifactKind.chapterGist,
    int? start = 0,
    int? end = 0,
  }) =>
      DistillArtifact(
        id: 'art-$key',
        bookId: 'book-1',
        kind: kind,
        unitKey: key,
        title: '第一章',
        body: '梗概',
        dataJson: '{}',
        chapterStart: start,
        chapterEnd: end,
        stale: false,
        createdAt: now,
      );

  test('saves and reads a job back', () async {
    await jobs.save(job());

    final loaded = await jobs.getByBook('book-1');
    expect(loaded, isNotNull);
    expect(loaded!.status, DistillStatus.running);
    expect(loaded.stage, DistillStage.map);
    expect(loaded.totalUnits, 3);
    expect(await jobs.getByBook('other'), isNull);
  });

  test('saving the same job id updates it', () async {
    await jobs.save(job());
    await jobs.save(job(status: 'completed', done: 3));

    final loaded = await jobs.getByBook('book-1');
    expect(loaded!.status, DistillStatus.completed);
    expect(loaded.doneUnits, 3);
  });

  test('doneKeys lists only finished units', () async {
    await units.put(unit('seg-0000'));
    await units.put(unit('seg-0001', status: 'pending'));

    expect(await units.doneKeys('job-1'), {'seg-0000'});
    expect(await units.doneKeys('job-2'), isEmpty);
  });

  test('putting the same unit key twice upserts instead of throwing', () async {
    await units.put(unit('seg-0000', status: 'pending'));
    await units.put(unit('seg-0000'));

    expect(await units.doneKeys('job-1'), {'seg-0000'});
  });

  test('artifact listing filters by kind and orders by unit key', () async {
    await artifacts.put(artifact('gist-0002', end: 1));
    await artifacts.put(artifact('gist-0001'));
    await artifacts.put(artifact('overview', kind: DistillArtifactKind.overview));

    final gists = await artifacts.listByBook(
      'book-1',
      kind: DistillArtifactKind.chapterGist,
    );
    expect(gists.map((a) => a.unitKey), ['gist-0001', 'gist-0002']);
    expect(gists.first.kind, DistillArtifactKind.chapterGist);
    expect(await artifacts.listByBook('book-1'), hasLength(3));
  });

  test('markStale flips every artifact of the book', () async {
    await artifacts.put(artifact('gist-0001'));
    await artifacts.put(artifact('overview', kind: DistillArtifactKind.overview));

    await artifacts.markStale('book-1');

    final all = await artifacts.listByBook('book-1');
    expect(all.every((a) => a.stale), isTrue);
  });

  test('deleting a book clears its distill rows', () async {
    await jobs.save(job());
    await units.put(unit('seg-0000'));
    await artifacts.put(artifact('gist-0001'));

    await units.deleteForBook('book-1');
    await artifacts.deleteForBook('book-1');
    await jobs.deleteForBook('book-1');

    expect(await jobs.getByBook('book-1'), isNull);
    expect(await units.doneKeys('job-1'), isEmpty);
    expect(await artifacts.listByBook('book-1'), isEmpty);
  });
}
