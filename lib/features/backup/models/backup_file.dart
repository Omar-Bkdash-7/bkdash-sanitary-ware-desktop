import 'dart:io';

/// A backup stored on the phone.
final class BackupFile {
  const BackupFile({
    required this.file,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });

  final File file;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  /// "1.2 MB" / "340 KB"
  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).ceil()} KB';
  }
}
