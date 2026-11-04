/// Persisted state of a book distillation run.
enum DistillStatus { queued, running, paused, completed, failed, canceled }

/// Pipeline stage the run is currently in.
enum DistillStage { plan, map, reduce1, reduce2, cards, verify }

/// Kinds of artifact the pipeline writes.
enum DistillArtifactKind { overview, tone, chapterGist, card }

class DistillJob {
  const DistillJob({
    required this.id,
    required this.bookId,
    required this.contentHash,
    required this.status,
    required this.stage,
    required this.pipelineVersion,
    required this.totalUnits,
    required this.doneUnits,
    required this.createdAt,
    required this.updatedAt,
    this.errorText,
  });

  final String id;
  final String bookId;
  final String contentHash;
  final DistillStatus status;
  final DistillStage stage;
  final int pipelineVersion;
  final int totalUnits;
  final int doneUnits;
  final String? errorText;
  final DateTime createdAt;
  final DateTime updatedAt;

  DistillJob copyWith({
    DistillStatus? status,
    DistillStage? stage,
    int? totalUnits,
    int? doneUnits,
    String? errorText,
    DateTime? updatedAt,
  }) {
    return DistillJob(
      id: id,
      bookId: bookId,
      contentHash: contentHash,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      pipelineVersion: pipelineVersion,
      totalUnits: totalUnits ?? this.totalUnits,
      doneUnits: doneUnits ?? this.doneUnits,
      errorText: errorText,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DistillUnit {
  const DistillUnit({
    required this.id,
    required this.jobId,
    required this.unitKey,
    required this.kind,
    required this.status,
    required this.attempts,
    required this.updatedAt,
    this.resultJson,
  });

  final String id;
  final String jobId;
  final String unitKey;
  final String kind;
  final String status;
  final String? resultJson;
  final int attempts;
  final DateTime updatedAt;
}

class DistillArtifact {
  const DistillArtifact({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.unitKey,
    required this.title,
    required this.body,
    required this.dataJson,
    required this.stale,
    required this.createdAt,
    this.chapterStart,
    this.chapterEnd,
  });

  final String id;
  final String bookId;
  final DistillArtifactKind kind;
  final String unitKey;
  final String title;
  final String body;
  final String dataJson;
  final int? chapterStart;
  final int? chapterEnd;
  final bool stale;
  final DateTime createdAt;
}
