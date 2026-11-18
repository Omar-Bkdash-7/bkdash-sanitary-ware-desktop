import 'package:bkdash_sanitary_ware/features/telegram/models/sync_job.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The queue of deliveries waiting for Telegram.
abstract interface class SyncQueueStore {
  /// Adds a pending job and returns its id.
  Future<int> add({
    required SyncJobKind kind,
    required DateTime createdAt,
    int? invoiceId,
    String filePath = '',
    String caption = '',
  });

  /// Pending jobs whose backoff has run out, oldest first.
  Future<List<SyncJob>> due({required DateTime now});

  /// The last few jobs of any status, newest first (the send-log screen).
  Future<List<SyncJob>> recent({int limit = 50});

  /// Pending jobs of one kind (used to keep a single database snapshot).
  Future<List<SyncJob>> pendingOfKind(SyncJobKind kind);

  Future<int> pendingCount();

  Future<void> markSent(int id);

  Future<void> markRetry(
    int id, {
    required int attempts,
    required String error,
    required DateTime nextAttemptAt,
  });

  Future<void> markFailed(
    int id, {
    required int attempts,
    required String error,
  });

  /// Makes every pending job due now (the manual "retry" button).
  Future<void> resetRetries({required DateTime now});

  /// Deletes all but the newest [keep] sent rows, so the log file stops
  /// growing while it still fills the send-log screen.
  Future<void> pruneSent({int keep = 50});

  Future<void> remove(int id);

  Future<void> close();
}

/// [SyncQueueStore] on its own SQLite file, next to the business database.
///
/// A separate file matters: [DbSnapshotService] copies only
/// `bkdash_sanitary_ware.db`, so no queue entry can ever appear inside a
/// snapshot that is uploaded or restored.
final class SqfliteSyncQueueStore implements SyncQueueStore {
  SqfliteSyncQueueStore._(this._db);

  static const String fileName = 'bkdash_sync_queue.db';

  final Database _db;

  static Future<SqfliteSyncQueueStore> open({
    DatabaseFactory? factory,
    String? directory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final folder = directory ?? await dbFactory.getDatabasesPath();
    final database = await dbFactory.openDatabase(
      p.join(folder, fileName),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  invoice_id INTEGER,
  file_path TEXT NOT NULL DEFAULT '',
  caption TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  last_error TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending'
)''');
          await db.execute('CREATE INDEX idx_outbox_status ON outbox (status)');
        },
      ),
    );
    return SqfliteSyncQueueStore._(database);
  }

  @override
  Future<int> add({
    required SyncJobKind kind,
    required DateTime createdAt,
    int? invoiceId,
    String filePath = '',
    String caption = '',
  }) => _db.insert('outbox', <String, Object?>{
    'kind': kind.name,
    'invoice_id': invoiceId,
    'file_path': filePath,
    'caption': caption,
    'created_at': createdAt.toIso8601String(),
    'attempts': 0,
    'status': SyncJobStatus.pending.name,
  });

  @override
  Future<List<SyncJob>> due({required DateTime now}) async {
    final rows = await _db.query(
      'outbox',
      where: 'status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: <Object?>[SyncJobStatus.pending.name, now.toIso8601String()],
      orderBy: 'id ASC',
    );
    return rows.map(SyncJob.fromRow).toList();
  }

  @override
  Future<List<SyncJob>> recent({int limit = 50}) async {
    final rows = await _db.query('outbox', orderBy: 'id DESC', limit: limit);
    return rows.map(SyncJob.fromRow).toList();
  }

  @override
  Future<List<SyncJob>> pendingOfKind(SyncJobKind kind) async {
    final rows = await _db.query(
      'outbox',
      where: 'status = ? AND kind = ?',
      whereArgs: <Object?>[SyncJobStatus.pending.name, kind.name],
      orderBy: 'id ASC',
    );
    return rows.map(SyncJob.fromRow).toList();
  }

  @override
  Future<int> pendingCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM outbox WHERE status = ?',
      <Object?>[SyncJobStatus.pending.name],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  @override
  Future<void> markSent(int id) => _db.update(
    'outbox',
    <String, Object?>{'status': SyncJobStatus.sent.name, 'last_error': ''},
    where: 'id = ?',
    whereArgs: <Object?>[id],
  );

  @override
  Future<void> markRetry(
    int id, {
    required int attempts,
    required String error,
    required DateTime nextAttemptAt,
  }) => _db.update(
    'outbox',
    <String, Object?>{
      'attempts': attempts,
      'last_error': error,
      'next_attempt_at': nextAttemptAt.toIso8601String(),
      'status': SyncJobStatus.pending.name,
    },
    where: 'id = ?',
    whereArgs: <Object?>[id],
  );

  @override
  Future<void> markFailed(
    int id, {
    required int attempts,
    required String error,
  }) => _db.update(
    'outbox',
    <String, Object?>{
      'attempts': attempts,
      'last_error': error,
      'status': SyncJobStatus.failed.name,
    },
    where: 'id = ?',
    whereArgs: <Object?>[id],
  );

  @override
  Future<void> resetRetries({required DateTime now}) => _db.update(
    'outbox',
    <String, Object?>{
      'next_attempt_at': now.toIso8601String(),
      'status': SyncJobStatus.pending.name,
    },
    where: 'status IN (?, ?)',
    whereArgs: <Object?>[SyncJobStatus.pending.name, SyncJobStatus.failed.name],
  );

  @override
  Future<void> pruneSent({int keep = 50}) => _db.rawDelete(
    'DELETE FROM outbox WHERE status = ? AND id NOT IN '
    '(SELECT id FROM outbox WHERE status = ? ORDER BY id DESC LIMIT ?)',
    <Object?>[SyncJobStatus.sent.name, SyncJobStatus.sent.name, keep],
  );

  @override
  Future<void> remove(int id) =>
      _db.delete('outbox', where: 'id = ?', whereArgs: <Object?>[id]);

  @override
  Future<void> close() => _db.close();
}
