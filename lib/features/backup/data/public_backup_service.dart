import 'dart:io';

import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_storage.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/public_backup.dart';

/// Keeps the last few database copies in a public folder.
///
/// The copies live in `Downloads/Bkdash_Backups`, outside the app, so they
/// survive uninstalling the app or losing the phone's app data. Nothing here
/// asks for all-files access: MediaStore owns the folder.
class PublicBackupService {
  PublicBackupService({
    required PublicBackupStorage storage,
    required KeyValueStore preferences,
    this.keepCount = keepLast,
  }) : _storage = storage,
       _preferences = preferences;

  /// How many copies are kept (the oldest are deleted).
  static const int keepLast = 10;

  static const String enabledKey = 'backups.public_enabled';

  /// Where the copies appear on the phone.
  static const String folderPath = 'Download/Bkdash_Backups';

  final PublicBackupStorage _storage;
  final KeyValueStore _preferences;
  final int keepCount;

  Future<bool> isSupported() => _storage.isSupported();

  Future<bool> isEnabled() async =>
      (await _preferences.getBool(enabledKey)) ?? false;

  Future<void> setEnabled(bool enabled) =>
      _preferences.setBool(enabledKey, enabled);

  /// Copies [file] into the public folder and deletes all but the newest
  /// [keepCount] copies. Does nothing while the switch is off.
  Future<PublicBackup?> keep(File file, {required String fileName}) async {
    if (!await isEnabled()) return null;
    final saved = await _storage.save(
      fileName: fileName,
      bytes: await file.readAsBytes(),
    );
    for (final old in (await _storage.list()).skip(keepCount)) {
      try {
        await _storage.delete(old.id);
      } catch (_) {
        // A copy written before a reinstall belongs to nobody: leave it.
      }
    }
    return saved;
  }

  /// The copies in the folder, newest first.
  Future<List<PublicBackup>> list() => _storage.list();
}
