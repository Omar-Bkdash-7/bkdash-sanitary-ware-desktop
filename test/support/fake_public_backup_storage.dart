import 'dart:typed_data';

import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_storage.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/public_backup.dart';

/// [PublicBackupStorage] kept in memory, newest first like the real folder.
final class FakePublicBackupStorage implements PublicBackupStorage {
  FakePublicBackupStorage({this.supported = true});

  final bool supported;

  final List<PublicBackup> copies = <PublicBackup>[];
  final List<String> names = <String>[];
  final List<String> deleted = <String>[];

  /// Saves made even while the folder could not be written.
  String? failure;

  var _nextId = 1;
  var _clock = DateTime(2026, 11, 16, 9);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<PublicBackup> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (failure != null) throw StateError(failure!);
    names.add(fileName);
    _clock = _clock.add(const Duration(minutes: 1));
    final copy = PublicBackup(
      id: '${_nextId++}',
      name: fileName,
      savedAt: _clock,
    );
    copies.insert(0, copy);
    return copy;
  }

  @override
  Future<List<PublicBackup>> list() async => List<PublicBackup>.of(copies);

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    copies.removeWhere((copy) => copy.id == id);
  }
}
