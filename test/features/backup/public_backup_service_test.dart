import 'dart:io';

import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_public_backup_storage.dart';
import '../../support/in_memory_key_value_store.dart';

void main() {
  late Directory folder;
  late FakePublicBackupStorage storage;
  late InMemoryKeyValueStore preferences;
  late PublicBackupService service;

  Future<File> snapshot(String name) async {
    final file = File(p.join(folder.path, name));
    await file.writeAsString('SQLITE');
    return file;
  }

  setUp(() async {
    folder = Directory(
      p.join(
        Directory.systemTemp.path,
        'bkdash_public_test_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await folder.create(recursive: true);
    storage = FakePublicBackupStorage();
    preferences = InMemoryKeyValueStore();
    service = PublicBackupService(storage: storage, preferences: preferences);
  });

  tearDown(() async {
    if (folder.existsSync()) await folder.delete(recursive: true);
  });

  test('nothing is copied while the switch is off', () async {
    final copy = await service.keep(
      await snapshot('bkdash_2026-11-16_09-00.db'),
      fileName: 'bkdash_2026-11-16_09-00.db',
    );

    expect(copy, isNull);
    expect(storage.names, isEmpty);
  });

  test('only the newest copies are kept', () async {
    await service.setEnabled(true);

    for (var minute = 0; minute < 12; minute++) {
      final name =
          'bkdash_2026-11-16_09-${minute.toString().padLeft(2, '0')}.db';
      await service.keep(await snapshot(name), fileName: name);
    }

    expect(storage.names, hasLength(12));
    expect(storage.copies, hasLength(PublicBackupService.keepLast));
    // The two oldest copies are gone; the ten newest are still there.
    expect(storage.deleted, hasLength(2));
    expect(
      storage.copies.map((copy) => copy.name),
      isNot(contains('bkdash_2026-11-16_09-00.db')),
    );
    expect(
      storage.copies.map((copy) => copy.name),
      contains('bkdash_2026-11-16_09-11.db'),
    );
  });

  test('the switch survives a new service instance', () async {
    await service.setEnabled(true);

    final reopened = PublicBackupService(
      storage: storage,
      preferences: preferences,
    );

    expect(await reopened.isEnabled(), isTrue);
    expect(await service.isEnabled(), isTrue);
  });
}
