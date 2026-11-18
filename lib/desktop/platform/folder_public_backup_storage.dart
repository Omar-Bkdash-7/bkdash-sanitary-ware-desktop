import 'dart:io';
import 'dart:typed_data';

import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_storage.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/public_backup.dart';
import 'package:path/path.dart' as p;

/// The rolling database copies, kept in an ordinary folder
/// (`Documents\Bkdash\AutoBackups`).
///
/// On the phone this needs MediaStore; on a computer a plain folder is enough,
/// and it is visible in Explorer, so a copy can be taken to another disk.
final class FolderPublicBackupStorage implements PublicBackupStorage {
  const FolderPublicBackupStorage(this.folder);

  final Directory folder;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<PublicBackup> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    await folder.create(recursive: true);
    final safe = _safeName(fileName);
    final stem = p.basenameWithoutExtension(safe);
    final extension = p.extension(safe);
    var target = File(p.join(folder.path, safe));
    var index = 2;
    while (target.existsSync()) {
      target = File(p.join(folder.path, '${stem}_$index$extension'));
      index++;
    }
    await target.writeAsBytes(bytes, flush: true);
    final name = p.basename(target.path);
    return PublicBackup(id: name, name: name, savedAt: DateTime.now());
  }

  @override
  Future<List<PublicBackup>> list() async {
    if (!folder.existsSync()) return const <PublicBackup>[];
    final copies = <PublicBackup>[
      for (final entity in folder.listSync())
        if (entity is File && entity.path.toLowerCase().endsWith('.db'))
          PublicBackup(
            id: p.basename(entity.path),
            name: p.basename(entity.path),
            savedAt: entity.statSync().modified,
          ),
    ];
    copies.sort((a, b) {
      final byTime = b.savedAt.compareTo(a.savedAt);
      return byTime != 0 ? byTime : b.name.compareTo(a.name);
    });
    return copies;
  }

  @override
  Future<void> delete(String id) async {
    final name = p.basename(id);
    // An id is a bare file name: never follow a path out of the folder.
    if (name.isEmpty || name != id) return;
    final file = File(p.join(folder.path, name));
    if (file.existsSync()) await file.delete();
  }

  /// A bare file name that Windows accepts: every separator and every character
  /// it forbids becomes `_`, so a name can never point outside the folder.
  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'backup.db';
    }
    return cleaned;
  }
}
