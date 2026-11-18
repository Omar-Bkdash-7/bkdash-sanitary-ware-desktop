import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Builds temporary, self-consistent copies of the live database for upload.
///
/// The live file is never sent as it is: SQLite may still be writing a page or
/// holding one in the journal, and a half-written file is worse than none.
/// A snapshot is built, checked with `PRAGMA quick_check`, handed to the
/// caller and deleted once it reached its destination.
class DbSnapshotService {
  DbSnapshotService({
    required AppDatabase database,
    required Future<Directory> Function() snapshotDirectory,
    Clock? clock,
  }) : _database = database,
       _snapshotDirectory = snapshotDirectory,
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final Future<Directory> Function() _snapshotDirectory;
  final Clock _clock;

  /// SQLite learnt `VACUUM INTO` in 3.27 (Android 10+ ships a newer one).
  static const int _vacuumIntoVersion = 327;

  /// Builds `bkdash_<yyyy-MM-dd>_<HH-mm>.db` inside the snapshots folder.
  ///
  /// [date] is the invoice date when an invoice triggered the snapshot, and
  /// today otherwise; the clock part is always the current time, so two
  /// snapshots of the same day never share a name.
  Future<BackupFile> create({DateTime? date}) async {
    final folder = await _snapshotDirectory();
    await folder.create(recursive: true);
    final when = date ?? _clock();
    final target = File(
      p.join(
        folder.path,
        'bkdash_${AppDates.isoDate(when)}_${AppDates.fileClock(_clock())}.db',
      ),
    );
    try {
      if (target.existsSync()) await target.delete();
      if (!await _tryVacuumInto(target)) await _copyQuietly(target);
      final problem = await AppDatabase.quickCheckFile(target);
      if (problem != null) {
        throw const BackupException(
          'تعذّر إنشاء نسخة سليمة من قاعدة البيانات.',
        );
      }
      return _describe(target);
    } on FileSystemException {
      await disposeFile(target);
      throw const BackupException(
        'تعذّر إنشاء نسخة مؤقتة من قاعدة البيانات (مساحة التخزين).',
      );
    }
  }

  /// Deletes a snapshot after it was uploaded (or is no longer needed).
  Future<void> dispose(BackupFile snapshot) => disposeFile(snapshot.file);

  /// Deletes [file] when it still exists; never throws.
  Future<void> disposeFile(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // A leftover temporary file is harmless.
    }
  }

  /// A consistent copy in one statement; the target must not exist yet.
  Future<bool> _tryVacuumInto(File target) async {
    final rows = await _database.db.rawQuery(
      'SELECT sqlite_version() AS version',
    );
    final version = '${rows.first['version']}';
    if (_versionNumber(version) < _vacuumIntoVersion) return false;
    try {
      final escaped = target.path.replaceAll("'", "''");
      await _database.db.execute("VACUUM INTO '$escaped'");
      return true;
    } on DatabaseException {
      // An old bundled SQLite (or a locked file): fall back to a plain copy.
      return false;
    }
  }

  /// Copy for SQLite versions without `VACUUM INTO`.
  ///
  /// The copy runs inside a transaction: `sqflite` serves every statement on
  /// one connection, so no other write can slip in between the checkpoint and
  /// the copy.
  Future<void> _copyQuietly(File target) async {
    await _database.db.transaction((txn) async {
      try {
        await txn.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } on DatabaseException {
        // Not in WAL mode: every committed page is already in the main file.
      }
      await File(_database.path).copy(target.path);
    });
  }

  /// "3.28.0" -> 328 (major * 100 + minor).
  static int _versionNumber(String text) {
    final parts = text.split('.');
    int part(int index) {
      if (index >= parts.length) return 0;
      final digits = parts[index].replaceAll(RegExp('[^0-9]'), '');
      return int.tryParse(digits) ?? 0;
    }

    return part(0) * 100 + part(1);
  }

  BackupFile _describe(File file) {
    final stat = file.statSync();
    return BackupFile(
      file: file,
      name: p.basename(file.path),
      sizeBytes: stat.size,
      modified: stat.modified,
    );
  }
}
