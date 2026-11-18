import 'package:bkdash_sanitary_ware/features/backup/models/public_backup.dart';
import 'package:flutter/services.dart';

/// The public folder that keeps the rolling copies.
///
/// It is a platform feature, not a plain directory: the copies must survive
/// uninstalling the app, which no app-private folder does.
abstract interface class PublicBackupStorage {
  /// `false` where MediaStore downloads do not exist (Android below 10).
  Future<bool> isSupported();

  Future<PublicBackup> save({
    required String fileName,
    required Uint8List bytes,
  });

  /// Every copy in the folder, newest first.
  Future<List<PublicBackup>> list();

  Future<void> delete(String id);
}

/// [PublicBackupStorage] on `Downloads/Bkdash_Backups` through MediaStore.
///
/// MediaStore needs no storage permission from Android 10 on, and the folder
/// is visible in the phone's file manager, so the copy can be moved to a
/// computer by hand.
final class MediaStorePublicBackupStorage implements PublicBackupStorage {
  const MediaStorePublicBackupStorage();

  static const MethodChannel _channel = MethodChannel('bkdash/public_backup');

  @override
  Future<bool> isSupported() async =>
      (await _channel.invokeMethod<bool>('isSupported')) ?? false;

  @override
  Future<PublicBackup> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final id = await _channel.invokeMethod<String>('save', <String, Object?>{
      'name': fileName,
      'bytes': bytes,
    });
    return PublicBackup(id: id ?? '', name: fileName, savedAt: DateTime.now());
  }

  @override
  Future<List<PublicBackup>> list() async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('list') ??
        const <Map<Object?, Object?>>[];
    return rows.map((row) {
      final seconds = row['savedAt'];
      return PublicBackup(
        id: (row['id'] as String?) ?? '',
        name: (row['name'] as String?) ?? '',
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          seconds is int ? seconds : 0,
        ),
      );
    }).toList();
  }

  @override
  Future<void> delete(String id) async {
    await _channel.invokeMethod<bool>('delete', <String, Object?>{'id': id});
  }
}
