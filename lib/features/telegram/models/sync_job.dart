/// What a queued delivery carries.
enum SyncJobKind {
  /// The PDF of one invoice (one job per invoice).
  invoicePdf,

  /// A snapshot of the whole database (only the newest one is kept).
  database,
}

/// Where a queued delivery stands.
enum SyncJobStatus { pending, sent, failed }

/// One delivery waiting for Telegram.
///
/// The queue lives in its own small database, never in the business database,
/// so it is not part of the snapshots that get uploaded.
final class SyncJob {
  const SyncJob({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.invoiceId,
    this.filePath = '',
    this.caption = '',
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError = '',
    this.status = SyncJobStatus.pending,
  });

  final int id;
  final SyncJobKind kind;
  final DateTime createdAt;

  /// The invoice of an `invoicePdf` job.
  final int? invoiceId;

  /// The ready snapshot file of a `database` job.
  final String filePath;

  /// The Arabic caption sent with the file.
  final String caption;

  /// How many delivery attempts already failed.
  final int attempts;

  /// No attempt before this moment (backoff / Telegram `retry_after`).
  final DateTime? nextAttemptAt;

  final String lastError;
  final SyncJobStatus status;

  bool isDue(DateTime now) =>
      status == SyncJobStatus.pending &&
      (nextAttemptAt == null || !nextAttemptAt!.isAfter(now));

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id == 0 ? null : id,
    'kind': kind.name,
    'invoice_id': invoiceId,
    'file_path': filePath,
    'caption': caption,
    'created_at': createdAt.toIso8601String(),
    'attempts': attempts,
    'next_attempt_at': nextAttemptAt?.toIso8601String(),
    'last_error': lastError,
    'status': status.name,
  };

  factory SyncJob.fromRow(Map<String, Object?> row) => SyncJob(
    id: row['id']! as int,
    kind: SyncJobKind.values.firstWhere(
      (kind) => kind.name == row['kind'],
      orElse: () => SyncJobKind.database,
    ),
    invoiceId: row['invoice_id'] as int?,
    filePath: (row['file_path'] as String?) ?? '',
    caption: (row['caption'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((row['created_at'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    attempts: (row['attempts'] as int?) ?? 0,
    nextAttemptAt: DateTime.tryParse((row['next_attempt_at'] as String?) ?? ''),
    lastError: (row['last_error'] as String?) ?? '',
    status: SyncJobStatus.values.firstWhere(
      (status) => status.name == row['status'],
      orElse: () => SyncJobStatus.pending,
    ),
  );
}
