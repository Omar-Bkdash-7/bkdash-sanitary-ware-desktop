import 'dart:async';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_coordinator.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_queue_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_settings_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/sync_job.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_public_backup_storage.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/in_memory_secret_store.dart';

/// A queue that lives in memory.
final class FakeQueue implements SyncQueueStore {
  final List<SyncJob> jobs = <SyncJob>[];
  int _nextId = 1;

  @override
  Future<int> add({
    required SyncJobKind kind,
    required DateTime createdAt,
    int? invoiceId,
    String filePath = '',
    String caption = '',
  }) async {
    final id = _nextId++;
    jobs.add(
      SyncJob(
        id: id,
        kind: kind,
        createdAt: createdAt,
        invoiceId: invoiceId,
        filePath: filePath,
        caption: caption,
      ),
    );
    return id;
  }

  @override
  Future<List<SyncJob>> due({required DateTime now}) async =>
      jobs.where((job) => job.isDue(now)).toList();

  @override
  Future<List<SyncJob>> recent({int limit = 50}) async =>
      jobs.reversed.take(limit).toList();

  @override
  Future<List<SyncJob>> pendingOfKind(SyncJobKind kind) async => jobs
      .where((job) => job.kind == kind && job.status == SyncJobStatus.pending)
      .toList();

  @override
  Future<int> pendingCount() async =>
      jobs.where((job) => job.status == SyncJobStatus.pending).length;

  int _index(int id) => jobs.indexWhere((job) => job.id == id);

  SyncJob _copy(
    SyncJob job, {
    SyncJobStatus? status,
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
  }) => SyncJob(
    id: job.id,
    kind: job.kind,
    createdAt: job.createdAt,
    invoiceId: job.invoiceId,
    filePath: job.filePath,
    caption: job.caption,
    attempts: attempts ?? job.attempts,
    nextAttemptAt: nextAttemptAt ?? job.nextAttemptAt,
    lastError: lastError ?? job.lastError,
    status: status ?? job.status,
  );

  @override
  Future<void> markSent(int id) async =>
      jobs[_index(id)] = _copy(jobs[_index(id)], status: SyncJobStatus.sent);

  @override
  Future<void> markRetry(
    int id, {
    required int attempts,
    required String error,
    required DateTime nextAttemptAt,
  }) async => jobs[_index(id)] = _copy(
    jobs[_index(id)],
    attempts: attempts,
    lastError: error,
    nextAttemptAt: nextAttemptAt,
    status: SyncJobStatus.pending,
  );

  @override
  Future<void> markFailed(
    int id, {
    required int attempts,
    required String error,
  }) async => jobs[_index(id)] = _copy(
    jobs[_index(id)],
    attempts: attempts,
    lastError: error,
    status: SyncJobStatus.failed,
  );

  @override
  Future<void> resetRetries({required DateTime now}) async {
    for (var i = 0; i < jobs.length; i++) {
      if (jobs[i].status == SyncJobStatus.pending) {
        jobs[i] = _copy(jobs[i], nextAttemptAt: now);
      }
    }
  }

  @override
  Future<void> pruneSent({int keep = 50}) async {
    final sent = jobs.where((job) => job.status == SyncJobStatus.sent).toList();
    if (sent.length <= keep) return;
    for (final job in sent.take(sent.length - keep)) {
      jobs.remove(job);
    }
  }

  @override
  Future<void> remove(int id) async => jobs.removeAt(_index(id));

  @override
  Future<void> close() async {}
}

/// A telegram client that records what it sent, or refuses on demand.
final class FakeTelegram extends TelegramService {
  /// Files that reached Telegram.
  final List<String> sent = <String>[];

  /// Files whose upload started (before any [hold] gate).
  final List<String> started = <String>[];

  String? failure;

  /// Makes the next upload wait until the test completes it.
  Completer<void>? hold;

  @override
  Future<void> sendDocument({
    required TelegramSettings settings,
    required File file,
    required String fileName,
    String contentType = 'application/vnd.sqlite3',
    String? caption,
  }) async {
    started.add(fileName);
    final gate = hold;
    hold = null;
    if (gate != null) await gate.future;
    if (failure != null) throw TelegramException(failure!);
    sent.add(fileName);
  }
}

void main() {
  late Directory folder;
  late FakeQueue queue;
  late FakeTelegram telegram;
  late InMemoryKeyValueStore preferences;
  late TelegramSettingsStore settings;
  late DataChangeNotifier changes;
  var now = DateTime(2026, 11, 16, 12);

  InvoiceDetails details(int id) => InvoiceDetails(
    invoice: Invoice(
      id: id,
      customerId: 3,
      customerName: 'عمر',
      customerPhone: '',
      paymentMethod: PaymentMethod.cash,
      invoiceDate: '2026-11-16',
      createdAt: '2026-11-16T11:55:00',
      total: Money(1000),
      paid: Money(1000),
      profit: Money(200),
      notes: '',
    ),
    lines: <InvoiceLineRecord>[
      InvoiceLineRecord(
        itemName: 'صنف',
        category: 'أدوات',
        sku: 'ITM-1',
        unit: 'قطعة',
        quantity: 1,
        unitCost: Money(800),
        unitPrice: Money(1000),
      ),
    ],
    payments: const <PaymentRecord>[],
  );

  Future<File> buildPdf(InvoiceDetails invoice) async {
    final file = File(p.join(folder.path, 'invoice_${invoice.invoice.id}.pdf'));
    await file.writeAsString('PDF');
    return file;
  }

  Future<BackupFile> buildSnapshot() async {
    final file = File(
      p.join(folder.path, 'bkdash_${DateTime.now().microsecondsSinceEpoch}.db'),
    );
    await file.writeAsString('SQLITE');
    return BackupFile(
      file: file,
      name: p.basename(file.path),
      sizeBytes: 6,
      modified: DateTime(2026, 11, 16, 12),
    );
  }

  SyncCoordinator coordinator({
    Duration debounce = const Duration(seconds: 30),
    PublicBackupService? publicBackups,
  }) => SyncCoordinator(
    queue: queue,
    settings: settings,
    telegram: telegram,
    preferences: preferences,
    changes: changes,
    loadInvoice: (id) async => details(id),
    buildPdf: buildPdf,
    buildSnapshot: buildSnapshot,
    loadSummary: () async => const DataSummary(
      invoices: 1,
      customers: 1,
      products: 2,
      schemaVersion: 1,
    ),
    clock: () => now,
    snapshotDebounce: debounce,
    retryInterval: const Duration(hours: 1),
    publicBackups: publicBackups,
  );

  /// Waits for a condition instead of guessing how long work takes.
  Future<void> waitUntil(
    bool Function() condition, {
    String reason = 'condition',
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for $reason');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  bool sent(String suffix) =>
      telegram.sent.any((name) => name.endsWith(suffix));

  setUp(() async {
    folder = Directory(
      p.join(
        Directory.systemTemp.path,
        'bkdash_sync_test_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await folder.create(recursive: true);
    queue = FakeQueue();
    telegram = FakeTelegram();
    preferences = InMemoryKeyValueStore();
    changes = DataChangeNotifier();
    settings = TelegramSettingsStore(InMemorySecretStore(), preferences);
    await settings.save(const TelegramSettings(token: '123:abc', chatId: '55'));
    now = DateTime(2026, 11, 16, 12);
  });

  tearDown(() async {
    if (folder.existsSync()) await folder.delete(recursive: true);
  });

  test('a new invoice is uploaded as a PDF right away', () async {
    final sync = coordinator();
    unawaited(sync.start());
    changes.reportWrite(DataWrite.invoice, invoiceId: 7);

    await waitUntil(
      () => telegram.sent.contains('invoice_7.pdf'),
      reason: 'pdf',
    );
    await waitUntil(() => sync.pending.value == 0, reason: 'empty queue');
    expect(queue.jobs.single.status, SyncJobStatus.sent);
    sync.dispose();
  });

  test('a burst of changes produces one database snapshot', () async {
    final sync = coordinator(debounce: const Duration(milliseconds: 40));
    unawaited(sync.start());
    changes
      ..reportWrite(DataWrite.invoice, invoiceId: 1)
      ..markChanged()
      ..reportWrite(DataWrite.inventory)
      ..reportWrite(DataWrite.customers)
      ..reportWrite(DataWrite.payment);

    await waitUntil(() => sent('.db'), reason: 'snapshot');
    // A second change after the first snapshot must not queue a second one
    // before the debounce elapses again.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(
      queue.jobs.where((job) => job.kind == SyncJobKind.database),
      hasLength(1),
    );
    sync.dispose();
  });

  test(
    'a write during a slow send goes out without waiting for the timer',
    () async {
      // The periodic retry is an hour away, so only the drain loop can deliver.
      final sync = coordinator();
      unawaited(sync.start());

      final gate = Completer<void>();
      telegram.hold = gate;
      changes.reportWrite(DataWrite.invoice, invoiceId: 7);
      await waitUntil(
        () => telegram.started.contains('invoice_7.pdf'),
        reason: 'first upload to start',
      );

      // A second sale is saved while the first PDF is still uploading.
      changes.reportWrite(DataWrite.invoice, invoiceId: 8);
      await waitUntil(
        () =>
            queue.jobs
                .where((job) => job.kind == SyncJobKind.invoicePdf)
                .length ==
            2,
        reason: 'second job queued',
      );
      // Let the queuing write reach `flush()` before the first upload finishes.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // The first upload is still in flight and the second has not started yet.
      expect(telegram.sent, isEmpty);
      expect(telegram.started, <String>['invoice_7.pdf']);

      gate.complete();
      await waitUntil(
        () => telegram.sent.contains('invoice_8.pdf'),
        reason: 'second upload in the same drain',
      );
      expect(telegram.sent, <String>['invoice_7.pdf', 'invoice_8.pdf']);
      sync.dispose();
    },
  );

  test('the public copy is kept even when Telegram is off', () async {
    final storage = FakePublicBackupStorage();
    final publicBackups = PublicBackupService(
      storage: storage,
      preferences: preferences,
    );
    await publicBackups.setEnabled(true);
    await settings.save(const TelegramSettings()); // no token, no chat id

    final sync = coordinator(
      debounce: const Duration(milliseconds: 40),
      publicBackups: publicBackups,
    );
    unawaited(sync.start());
    changes.reportWrite(DataWrite.customers);

    await waitUntil(() => storage.names.isNotEmpty, reason: 'public copy');
    expect(storage.names.single, endsWith('.db'));
    expect(telegram.started, isEmpty);
    expect(await queue.pendingCount(), 0);
    sync.dispose();
  });

  test('a failed upload stays pending with a growing delay', () async {
    final sync = coordinator();
    unawaited(sync.start());
    telegram.failure = 'لا يوجد اتصال';
    changes.reportWrite(DataWrite.invoice, invoiceId: 3);

    await waitUntil(
      () => queue.jobs.isNotEmpty && queue.jobs.single.attempts == 1,
      reason: 'first attempt',
    );
    final job = queue.jobs.single;
    expect(job.status, SyncJobStatus.pending);
    expect(job.nextAttemptAt!.isAfter(now), isTrue);
    expect(job.lastError, 'لا يوجد اتصال');
    expect(sync.pending.value, 1);

    // The manual retry makes the job due again, even though it is not yet.
    await sync.retryNow();
    await waitUntil(
      () => queue.jobs.single.attempts == 2,
      reason: 'second attempt',
    );
    expect(queue.jobs.single.status, SyncJobStatus.pending);
    sync.dispose();
  });

  test('the pending snapshot survives a restart', () async {
    await preferences.setBool(SyncCoordinator.dirtyKey, true);
    final sync = coordinator();
    unawaited(sync.start());

    await waitUntil(() => sent('.db'), reason: 'recovered snapshot');
    expect(await preferences.getBool(SyncCoordinator.dirtyKey), isFalse);
    sync.dispose();
  });
}
