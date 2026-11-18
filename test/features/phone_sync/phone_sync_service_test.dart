import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/phone_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/telegram_inbox_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/import_plan.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_key_value_store.dart';
import '../../support/in_memory_secret_store.dart';

/// One device (the phone or the computer): a real SQLite database on disk with
/// the real services around it. Only Telegram is left out.
class _Device {
  _Device({
    required this.dir,
    required this.database,
    required this.backups,
    required this.snapshots,
    required this.service,
  });

  final Directory dir;
  final AppDatabase database;
  final BackupService backups;
  final DesktopSnapshotService snapshots;
  final PhoneSyncService service;
}

void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;

  late Directory root;
  late List<AppDatabase> opened;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bkdash_sync_');
    opened = <AppDatabase>[];
  });

  tearDown(() async {
    for (final database in opened) {
      await database.close();
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<_Device> openDevice(String name, {required bool seed}) async {
    final dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    final data = Directory(p.join(dir.path, 'data'))..createSync();
    final database = await AppDatabase.open(
      factory: factory,
      directory: data.path,
      seed: seed,
    );
    opened.add(database);
    final changes = DataChangeNotifier();
    final backups = BackupService(
      database: database,
      changes: changes,
      backupsDirectory: () async => Directory(p.join(dir.path, 'backups')),
    );
    final snapshots = DesktopSnapshotService(
      database: database,
      snapshotDirectory: () async => Directory(p.join(dir.path, 'snapshots')),
      factory: factory,
    );
    final store = InMemoryKeyValueStore();
    final service = PhoneSyncService(
      database: database,
      backups: backups,
      snapshots: snapshots,
      telegram: TelegramService(),
      inbox: TelegramInboxService(),
      settings: TelegramSettingsStore(InMemorySecretStore(), store),
      preferences: store,
      receivedDirectory: () async => Directory(p.join(dir.path, 'received')),
      factory: factory,
    );
    return _Device(
      dir: dir,
      database: database,
      backups: backups,
      snapshots: snapshots,
      service: service,
    );
  }

  Future<void> addInvoice(AppDatabase database, String createdAt) async {
    await database.db.insert('invoices', <String, Object?>{
      'customer_id': null,
      'customer_name': 'زبون',
      'customer_phone': '',
      'payment_method': 'cash',
      'invoice_date': createdAt.substring(0, 10),
      'created_at': createdAt,
      'total_cents': 3000,
      'paid_cents': 3000,
      'profit_cents': 1000,
      'notes': '',
    });
  }

  test('a new computer takes the phone data and keeps a safety copy', () async {
    final phone = await openDevice('phone', seed: false);
    await addInvoice(phone.database, '2026-11-10T10:00:00');
    await addInvoice(phone.database, '2026-11-10T11:00:00');
    final snapshot = await phone.snapshots.create();

    final desktop = await openDevice('desktop', seed: true);
    final prepared = await desktop.service.prepareFromFile(snapshot.file);

    expect(prepared.plan.verdict, ImportVerdict.freshLocal);
    expect(prepared.plan.incoming.invoices, 2);

    await desktop.service.applyImport(prepared);

    expect((await desktop.backups.summarize()).invoices, 2);
    final safety = desktop.dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('before_restore_'));
    expect(safety, isNotEmpty);
    final state = await desktop.service.loadState();
    expect(state.lastImport?.invoices, 2);
  });

  test('an older file over newer data is flagged before it is imported', () async {
    final phone = await openDevice('phone', seed: false);
    await addInvoice(phone.database, '2026-11-10T10:00:00');
    await addInvoice(phone.database, '2026-11-10T11:00:00');
    final old = await phone.snapshots.create();

    final desktop = await openDevice('desktop', seed: false);
    await desktop.service.applyImport(
      await desktop.service.prepareFromFile(old.file),
    );
    await addInvoice(desktop.database, '2026-11-11T09:00:00');

    final plan = (await desktop.service.prepareFromFile(old.file)).plan;

    expect(plan.verdict, ImportVerdict.incomingOlder);
    expect(plan.lost.invoices, 1);
    expect(plan.needsStrongWarning, isTrue);
  });

  test('invoices made on both devices without a sync are a divergence', () async {
    final phone = await openDevice('phone', seed: false);
    await addInvoice(phone.database, '2026-11-10T10:00:00');
    final base = await phone.snapshots.create();

    final desktop = await openDevice('desktop', seed: false);
    await desktop.service.applyImport(
      await desktop.service.prepareFromFile(base.file),
    );

    // Both devices now write "invoice number 2".
    await addInvoice(desktop.database, '2026-11-11T09:00:00');
    await addInvoice(phone.database, '2026-11-11T09:30:00');
    final phoneLater = await phone.snapshots.create();

    final plan = (await desktop.service.prepareFromFile(phoneLater.file)).plan;

    expect(plan.verdict, ImportVerdict.diverged);
    expect(plan.lost.invoices, 1);
    expect(plan.gained.invoices, 1);
  });

  test('the phone newer copy is a normal catch-up', () async {
    final phone = await openDevice('phone', seed: false);
    await addInvoice(phone.database, '2026-11-10T10:00:00');
    final base = await phone.snapshots.create();

    final desktop = await openDevice('desktop', seed: false);
    await desktop.service.applyImport(
      await desktop.service.prepareFromFile(base.file),
    );

    await addInvoice(phone.database, '2026-11-12T10:00:00');
    final later = await phone.snapshots.create();

    final plan = (await desktop.service.prepareFromFile(later.file)).plan;

    expect(plan.verdict, ImportVerdict.incomingNewer);
    expect(plan.gained.invoices, 1);
  });

  test('a file that is not a BKDash database is refused', () async {
    final desktop = await openDevice('desktop', seed: false);
    final junk = File(p.join(root.path, 'junk.db'))
      ..writeAsStringSync('this is not sqlite');

    await expectLater(
      desktop.service.prepareFromFile(junk),
      throwsA(isA<BackupException>()),
    );
  });

  test('database copies made by the computer are named and healthy', () async {
    final desktop = await openDevice('desktop', seed: true);
    final snapshot = await desktop.snapshots.create();

    expect(
      p.basename(snapshot.file.path),
      startsWith(DesktopSnapshotService.filePrefix),
    );
    expect(
      await AppDatabase.quickCheckFile(snapshot.file, factory: factory),
      isNull,
    );
  });

  test('sending to Telegram needs the bot to be set up first', () async {
    final desktop = await openDevice('desktop', seed: false);

    await expectLater(
      desktop.service.sendSnapshotNow(),
      throwsA(isA<TelegramException>()),
    );
  });
}
