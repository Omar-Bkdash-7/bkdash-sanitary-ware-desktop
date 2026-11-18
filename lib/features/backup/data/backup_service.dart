import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:path/path.dart' as p;

/// Creates, lists and restores copies of the whole database.
class BackupService {
  BackupService({
    required AppDatabase database,
    required DataChangeNotifier changes,
    required Future<Directory> Function() backupsDirectory,
    Clock? clock,
  }) : _database = database,
       _changes = changes,
       _backupsDirectory = backupsDirectory,
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Future<Directory> Function() _backupsDirectory;
  final Clock _clock;

  static const String _extension = '.db';

  /// Copies the database into a new, time-stamped file.
  Future<BackupFile> createBackup() async {
    try {
      final folder = await _backupsDirectory();
      final name = 'bkdash_backup_${AppDates.fileStamp(_clock())}$_extension';
      final target = File(p.join(folder.path, name));
      await _database.copyTo(target);
      return _describe(target);
    } on FileSystemException {
      throw const BackupException(
        'تعذّر إنشاء النسخة الاحتياطية (مساحة التخزين أو الصلاحيات).',
      );
    }
  }

  /// The backups kept on the phone, newest first.
  Future<List<BackupFile>> listBackups() async {
    final folder = await _backupsDirectory();
    if (!folder.existsSync()) return const <BackupFile>[];
    final files =
        folder
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith(_extension))
            .map(_describe)
            .toList()
          ..sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  Future<void> deleteBackup(BackupFile backup) async {
    if (backup.file.existsSync()) await backup.file.delete();
  }

  /// Counts of the data now on the phone.
  Future<DataSummary> summarize() => _database.summarize();

  /// Counts inside [source], after checking that it is a usable backup.
  ///
  /// Throws [BackupException] for a file that is not this app's data, so the
  /// confirmation dialog is shown only for a file that can really be restored.
  Future<DataSummary> summarizeIncoming(File source) async {
    await _database.validateBackup(source);
    return _database.summarizeFile(source);
  }

  /// Replaces the current data with the content of [source].
  ///
  /// The file is checked first and the current data is saved aside, so a failed
  /// or unwanted restore can be undone from the backups list.
  Future<void> restore(File source) async {
    await _database.validateBackup(source);
    final folder = await _backupsDirectory();
    final safety = File(
      p.join(
        folder.path,
        'before_restore_${AppDates.fileStamp(_clock())}$_extension',
      ),
    );
    try {
      await _database.copyTo(safety);
      await _database.replaceWith(source);
    } on FileSystemException {
      throw const BackupException('تعذّرت استعادة النسخة الاحتياطية.');
    }
    _changes.markChanged();
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
