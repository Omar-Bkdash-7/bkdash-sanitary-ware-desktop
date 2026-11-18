import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/services/file_sharer.dart';
import 'package:path/path.dart' as p;

/// Opens a file or shows it in the file manager.
abstract interface class FileLauncher {
  /// Opens [path] with the program the system associates with it.
  Future<void> open(String path);

  /// Shows [path] selected in the file manager.
  Future<void> reveal(String path);
}

/// [FileLauncher] backed by the operating system.
final class SystemFileLauncher implements FileLauncher {
  const SystemFileLauncher();

  @override
  Future<void> open(String path) async {
    try {
      if (Platform.isWindows) {
        // The empty argument is the (unused) window title `start` expects.
        await Process.run('cmd', <String>['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>[path]);
      } else {
        await Process.run('xdg-open', <String>[path]);
      }
    } on ProcessException {
      // The file is saved either way; only the convenience is lost.
    }
  }

  @override
  Future<void> reveal(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', <String>['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>['-R', path]);
      } else {
        await Process.run('xdg-open', <String>[p.dirname(path)]);
      }
    } on ProcessException {
      // The file is saved either way; only the convenience is lost.
    }
  }
}

/// [FileSharer] for a computer.
///
/// There is no share sheet on Windows, so "sharing" keeps a copy of the file in
/// the exports folder and then shows it: a PDF opens in the default viewer (from
/// where it can be printed), anything else is selected in Explorer.
final class DesktopFileSharer implements FileSharer {
  DesktopFileSharer({required this.folder, FileLauncher? launcher})
    : launcher = launcher ?? const SystemFileLauncher();

  final Directory folder;
  final FileLauncher launcher;

  @override
  Future<void> shareFile(File file, {String? subject, String? text}) async {
    if (!file.existsSync()) {
      throw const BackupException('الملف المطلوب غير موجود.');
    }
    final saved = await _keep(file);
    if (p.extension(saved.path).toLowerCase() == '.pdf') {
      await launcher.open(saved.path);
    } else {
      await launcher.reveal(saved.path);
    }
  }

  Future<File> _keep(File file) async {
    try {
      await folder.create(recursive: true);
      final target = File(p.join(folder.path, p.basename(file.path)));
      final same = p.equals(p.absolute(file.path), p.absolute(target.path));
      return same ? file : await file.copy(target.path);
    } on FileSystemException {
      throw const BackupException('تعذّر حفظ الملف في مجلد التصدير.');
    }
  }
}
