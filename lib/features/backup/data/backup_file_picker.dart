import 'dart:io';

/// Lets the user choose a backup file from the phone (Downloads, Drive, ...).
abstract interface class BackupFilePicker {
  /// A readable copy of the chosen file, or `null` when the user cancelled.
  Future<File?> pickBackup();
}
