import 'dart:io';

import 'package:path/path.dart' as p;

/// Lets only one copy of the program work on a data folder.
///
/// Two copies writing the same invoices database would give the two windows
/// different pictures of the stock, so the second copy is refused.
final class SingleInstanceLock {
  SingleInstanceLock._(this._file);

  final RandomAccessFile _file;

  static const String fileName = 'bkdash.lock';

  /// The lock, or `null` when another copy of the program already holds it.
  static Future<SingleInstanceLock?> acquire(Directory folder) async {
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, fileName));
    RandomAccessFile? handle;
    try {
      // Append mode: opening must not truncate a file another copy has locked.
      handle = await file.open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      return SingleInstanceLock._(handle);
    } on FileSystemException {
      await handle?.close();
      return null;
    }
  }

  Future<void> release() async {
    try {
      await _file.unlock();
    } on FileSystemException {
      // Closing the file releases the lock anyway.
    }
    await _file.close();
  }
}
