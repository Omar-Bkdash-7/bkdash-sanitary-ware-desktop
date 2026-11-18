import 'dart:io';

import 'package:bkdash_sanitary_ware/features/backup/data/backup_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

/// [BackupFilePicker] for a computer.
///
/// Unlike the phone's picker it keeps the chosen file's own name. The name is
/// what tells the owner, and the import check, whether a database came from the
/// phone (`bkdash_2026-…`) or from this very program (`bkdash_desktop_…`).
final class DesktopBackupPicker implements BackupFilePicker {
  const DesktopBackupPicker(this._folder);

  /// Where the chosen file is copied to, so the original is never touched.
  final Future<Directory> Function() _folder;

  @override
  Future<File?> pickBackup() async {
    final picked = await openFile(confirmButtonText: 'اختيار');
    if (picked == null) return null;
    final folder = await _folder();
    await folder.create(recursive: true);
    final target = File(p.join(folder.path, p.basename(picked.name)));
    if (target.existsSync()) await target.delete();
    await picked.saveTo(target.path);
    return target;
  }
}
