import 'dart:io';

import 'package:bkdash_sanitary_ware/features/backup/data/backup_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

/// [BackupFilePicker] backed by the `file_selector` plugin.
final class FileSelectorBackupPicker implements BackupFilePicker {
  const FileSelectorBackupPicker(this._temporaryDirectory);

  /// Where the chosen file is copied to (the app cannot always read the
  /// original location directly).
  final Future<Directory> Function() _temporaryDirectory;

  @override
  Future<File?> pickBackup() async {
    final picked = await openFile(confirmButtonText: 'اختيار');
    if (picked == null) return null;
    final folder = await _temporaryDirectory();
    final target = File(p.join(folder.path, 'restore_candidate.db'));
    await picked.saveTo(target.path);
    return target;
  }
}
