import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/db_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Builds the database copies that the computer uploads to Telegram.
///
/// It differs from the phone's [DbSnapshotService] in two ways:
///
/// * the file name starts with [filePrefix] (`bkdash_desktop_2026-11-16_19-02.db`),
///   so in the Telegram chat, in Downloads and in the restore picker it is
///   obvious which device produced the file and nobody imports a file in the
///   wrong direction;
/// * every database call uses the factory it was given instead of the global
///   default, which on Windows is not a working SQLite binding.
final class DesktopSnapshotService extends DbSnapshotService {
  DesktopSnapshotService({
    required super.database,
    required super.snapshotDirectory,
    required DatabaseFactory factory,
    super.clock,
  }) : _database = database,
       _folder = snapshotDirectory,
       _factory = factory,
       _clock = clock ?? DateTime.now;

  /// Start of every file name produced by the computer.
  static const String filePrefix = 'bkdash_desktop_';

  /// SQLite learnt `VACUUM INTO` in 3.27.
  static const int _vacuumIntoVersion = 327;

  final AppDatabase _database;
  final Future<Directory> Function() _folder;
  final DatabaseFactory _factory;
  final Clock _clock;

  @override
  Future<BackupFile> create({DateTime? date}) async {
    final folder = await _folder();
    await folder.create(recursive: true);
    final when = date ?? _clock();
    final target = File(
      p.join(
        folder.path,
        '$filePrefix${AppDates.isoDate(when)}_'
        '${AppDates.fileClock(_clock())}.db',
      ),
    );
    try {
      if (target.existsSync()) await target.delete();
      if (!await _tryVacuumInto(target)) await _copyQuietly(target);
      final problem = await AppDatabase.quickCheckFile(
        target,
        factory: _factory,
      );
      if (problem != null) {
        await disposeFile(target);
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
      return false;
    }
  }

  /// Copy for SQLite versions without `VACUUM INTO`, taken inside a transaction
  /// so no other write can slip in between the checkpoint and the copy.
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
