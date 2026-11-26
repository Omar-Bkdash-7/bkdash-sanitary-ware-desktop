import 'dart:io';

import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/services/file_sharer.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_file_picker.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/export_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/public_backup.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/restore_preview.dart';

/// The Excel files the user can export.
enum ExportKind {
  inventory('المخزون'),
  invoices('الفواتير'),
  invoiceLines('الأصناف المباعة'),
  purchases('الشراء من الزبائن'),
  purchaseLines('الأصناف المشتراة'),
  customers('الزبائن والأرصدة'),
  returns('المرتجعات'),
  returnLines('أصناف المرتجعات');

  const ExportKind(this.label);

  final String label;
}

/// Backup, restore and export (the "data tools" screen).
class DataToolsController extends BaseController {
  DataToolsController({
    required BackupService backups,
    required ExportService exports,
    required BackupFilePicker picker,
    required FileSharer sharer,
    required PublicBackupService publicBackups,
  }) : _backups = backups,
       _exports = exports,
       _picker = picker,
       _sharer = sharer,
       _publicBackups = publicBackups;

  final BackupService _backups;
  final ExportService _exports;
  final BackupFilePicker _picker;
  final FileSharer _sharer;
  final PublicBackupService _publicBackups;

  List<BackupFile> _files = const <BackupFile>[];
  List<PublicBackup> _publicCopies = const <PublicBackup>[];
  bool _publicEnabled = false;
  bool _publicSupported = true;
  bool _busy = false;

  List<BackupFile> get backups => _files;

  /// The copies in the public folder.
  List<PublicBackup> get publicCopies => _publicCopies;

  bool get publicEnabled => _publicEnabled;

  /// `false` on Android versions without MediaStore downloads.
  bool get publicSupported => _publicSupported;

  /// `true` while a backup, restore or export is running.
  bool get isBusy => _busy;

  Future<void> load() => runLoad(() async {
    _files = await _backups.listBackups();
    _publicSupported = await _publicBackups.isSupported();
    _publicEnabled = await _publicBackups.isEnabled();
    _publicCopies = await _publicCopyList();
  });

  /// Keeps a copy of every change in the public folder, or stops doing so.
  Future<void> setPublicBackups({required bool enabled}) => _guard(() async {
    await _publicBackups.setEnabled(enabled);
    _publicEnabled = enabled;
    _publicCopies = await _publicCopyList();
  });

  /// The folder may be unreadable on an unsupported device: show none.
  Future<List<PublicBackup>> _publicCopyList() async {
    if (!_publicSupported) return const <PublicBackup>[];
    try {
      return await _publicBackups.list();
    } catch (_) {
      return const <PublicBackup>[];
    }
  }

  /// Creates a backup and returns it (the screen then offers to share it).
  Future<BackupFile> createBackup() => _guard(() async {
    final backup = await _backups.createBackup();
    _files = await _backups.listBackups();
    return backup;
  });

  Future<void> share(BackupFile backup) => _guard(
    () => _sharer.shareFile(
      backup.file,
      subject: 'نسخة احتياطية - بكداش',
      text: backup.name,
    ),
  );

  Future<void> delete(BackupFile backup) => _guard(() async {
    await _backups.deleteBackup(backup);
    _files = await _backups.listBackups();
  });

  /// Asks the user to choose a file; `null` when he cancelled.
  Future<File?> pickBackupFile() => _guard(_picker.pickBackup);

  /// Counts of the current data and of [source], for the confirmation dialog.
  Future<RestorePreview> previewRestore(File source) => _guard(() async {
    final current = await _backups.summarize();
    final incoming = await _backups.summarizeIncoming(source);
    return RestorePreview(current: current, incoming: incoming);
  });

  Future<void> restore(File source) => _guard(() async {
    await _backups.restore(source);
    _files = await _backups.listBackups();
  });

  Future<void> restoreStored(BackupFile backup) => restore(backup.file);

  /// Writes the Excel file of [kind] and opens the share sheet for it.
  Future<void> export(ExportKind kind) => _guard(() async {
    final file = switch (kind) {
      ExportKind.inventory => await _exports.exportInventory(),
      ExportKind.invoices => await _exports.exportInvoices(),
      ExportKind.invoiceLines => await _exports.exportInvoiceLines(),
      ExportKind.purchases => await _exports.exportPurchases(),
      ExportKind.purchaseLines => await _exports.exportPurchaseLines(),
      ExportKind.customers => await _exports.exportCustomers(),
      ExportKind.returns => await _exports.exportReturns(),
      ExportKind.returnLines => await _exports.exportReturnLines(),
    };
    await _sharer.shareFile(file, subject: 'بكداش - ${kind.label}');
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
