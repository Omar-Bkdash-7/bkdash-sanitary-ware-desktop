import 'dart:io';
import 'dart:typed_data';

import 'package:bkdash_sanitary_ware/desktop/platform/folder_public_backup_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory folder;
  late FolderPublicBackupStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bkdash_auto_');
    folder = Directory(p.join(root.path, 'AutoBackups'));
    storage = FolderPublicBackupStorage(folder);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  test('is always supported on a computer', () async {
    expect(await storage.isSupported(), isTrue);
  });

  test('creates the folder and saves the bytes', () async {
    final saved = await storage.save(
      fileName: 'bkdash_2026-11-16_09-41.db',
      bytes: bytes(<int>[1, 2, 3]),
    );
    expect(saved.name, 'bkdash_2026-11-16_09-41.db');
    expect(
      File(p.join(folder.path, saved.name)).readAsBytesSync(),
      <int>[1, 2, 3],
    );
  });

  test('never overwrites a copy that has the same name', () async {
    final first = await storage.save(fileName: 'a.db', bytes: bytes(<int>[1]));
    final second = await storage.save(fileName: 'a.db', bytes: bytes(<int>[2]));
    expect(first.name, 'a.db');
    expect(second.name, 'a_2.db');
    expect(File(p.join(folder.path, 'a.db')).readAsBytesSync(), <int>[1]);
  });

  test('lists only .db files, newest first', () async {
    await storage.save(fileName: 'old.db', bytes: bytes(<int>[1]));
    await storage.save(fileName: 'new.db', bytes: bytes(<int>[2]));
    File(p.join(folder.path, 'notes.txt')).writeAsStringSync('x');
    File(p.join(folder.path, 'old.db')).setLastModifiedSync(
      DateTime(2026, 1, 1),
    );
    File(p.join(folder.path, 'new.db')).setLastModifiedSync(
      DateTime(2026, 6, 1),
    );

    final copies = await storage.list();

    expect(copies.map((c) => c.name), <String>['new.db', 'old.db']);
  });

  test('lists nothing when the folder does not exist yet', () async {
    expect(await storage.list(), isEmpty);
  });

  test('deletes a copy by id', () async {
    final saved = await storage.save(fileName: 'a.db', bytes: bytes(<int>[1]));
    await storage.delete(saved.id);
    expect(await storage.list(), isEmpty);
  });

  test('never follows an id out of the folder', () async {
    await storage.save(fileName: 'a.db', bytes: bytes(<int>[1]));
    final outside = File(p.join(root.path, 'outside.db'))
      ..writeAsBytesSync(<int>[9]);

    await storage.delete('../outside.db');

    expect(outside.existsSync(), isTrue);
  });

  test('cleans characters Windows does not allow in a file name', () async {
    final saved = await storage.save(
      fileName: 'a:b?c.db',
      bytes: bytes(<int>[1]),
    );
    expect(saved.name, 'a_b_c.db');
  });
}
