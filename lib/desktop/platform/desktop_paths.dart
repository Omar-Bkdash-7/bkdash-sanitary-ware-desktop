import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the desktop program keeps its files.
///
/// * [data] holds the live databases. It is a local folder on purpose: the
///   Documents folder of Windows is often mirrored by OneDrive, and a sync
///   client must never touch a database that is open.
/// * Every other folder lives under `Documents\BKDash`, where the owner can see
///   it, copy it to a flash drive or let OneDrive keep it.
final class DesktopPaths {
  const DesktopPaths({
    required this.data,
    required this.backups,
    required this.autoCopies,
    required this.exports,
    required this.received,
    required this.temp,
  });

  /// The live databases (`bkdash_sanitary_ware.db`, `bkdash_sync_queue.db`).
  final Directory data;

  /// Manual backups and the safety copies taken before a restore or upgrade.
  final Directory backups;

  /// The rolling copies kept after every change ("automatic copies" switch).
  final Directory autoCopies;

  /// CSV files and invoice PDFs the user asked to keep.
  final Directory exports;

  /// Snapshots downloaded from Telegram, kept as a record of what was imported.
  final Directory received;

  /// Scratch space (the PDF or snapshot that is about to be uploaded).
  final Directory temp;

  /// Resolves the folders.
  ///
  /// The three roots exist for tests; the application uses the Windows
  /// defaults (`%LOCALAPPDATA%\BKDash` and `Documents\BKDash`).
  static Future<DesktopPaths> resolve({
    String? dataRoot,
    String? documentsRoot,
    String? tempRoot,
  }) async {
    final dataBase = dataRoot ?? await _defaultDataRoot();
    final documents =
        documentsRoot ??
        p.join((await getApplicationDocumentsDirectory()).path, 'BKDash');
    final scratch =
        tempRoot ?? p.join((await getTemporaryDirectory()).path, 'BKDash');
    return DesktopPaths(
      data: Directory(p.join(dataBase, 'data')),
      backups: Directory(p.join(documents, 'backups')),
      autoCopies: Directory(p.join(documents, 'AutoBackups')),
      exports: Directory(p.join(documents, 'exports')),
      received: Directory(p.join(documents, 'received')),
      temp: Directory(scratch),
    );
  }

  /// Every folder, in the order they are created.
  List<Directory> get all => <Directory>[
    data,
    backups,
    autoCopies,
    exports,
    received,
    temp,
  ];

  Future<void> ensureCreated() async {
    for (final directory in all) {
      await directory.create(recursive: true);
    }
  }

  static Future<String> _defaultDataRoot() async {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.trim().isNotEmpty) {
      return p.join(local, 'BKDash');
    }
    return p.join((await getApplicationSupportDirectory()).path, 'BKDash');
  }
}
