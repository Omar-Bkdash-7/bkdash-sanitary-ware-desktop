import 'dart:io';

/// Opens the system share sheet for a file (WhatsApp, Drive, e-mail, ...).
abstract interface class FileSharer {
  Future<void> shareFile(File file, {String? subject, String? text});
}
