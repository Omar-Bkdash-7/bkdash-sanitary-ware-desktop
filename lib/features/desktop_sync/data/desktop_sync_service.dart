import 'dart:async';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/desktop_bridge_client.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/sync_outbox.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/sync_settings_store.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/invoice_sync_payload.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/sync_settings.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:path/path.dart' as p;

/// Connects the shop phone to Telegram and to the bridge program on the shop
/// computer - all over the local network, with no cloud database.
///
/// Every new invoice is delivered twice: once to Telegram and once to the PC.
/// Deliveries that fail are kept in [SyncOutbox] and retried, so nothing is
/// lost when the Wi-Fi or the computer is off for a moment.
class DesktopSyncService {
  DesktopSyncService({
    required SyncSettingsStore settingsStore,
    required InvoiceRepository invoices,
    required BackupService backups,
    required SyncOutbox outbox,
    required AppDatabase database,
    required Future<Directory> Function() backupsDirectory,
    DesktopBridgeClient? bridge,
    Clock? clock,
  }) : _settingsStore = settingsStore,
       _invoices = invoices,
       _backups = backups,
       _outbox = outbox,
       _database = database,
       _backupsDirectory = backupsDirectory,
       _bridge = bridge ?? DesktopBridgeClient(),
       _clock = clock ?? DateTime.now;

  final SyncSettingsStore _settingsStore;
  final InvoiceRepository _invoices;
  final BackupService _backups;
  final SyncOutbox _outbox;
  final AppDatabase _database;
  final Future<Directory> Function() _backupsDirectory;
  final DesktopBridgeClient _bridge;
  final Clock _clock;

  Timer? _timer;
  bool _flushing = false;

  Future<SyncSettings> settings() => _settingsStore.load();

  Future<void> saveSettings(SyncSettings settings) =>
      _settingsStore.save(settings);

  /// How many invoices are still waiting for one of the two channels.
  Future<int> pendingCount() async => (await _outbox.load()).length;

  /// Starts retrying the queue once a minute; call once when the app opens.
  Future<void> start({
    Duration retryInterval = const Duration(minutes: 1),
  }) async {
    _timer ??= Timer.periodic(retryInterval, (_) => unawaited(flush()));
    await flush();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Queues a freshly saved invoice and delivers it right away.
  ///
  /// Never throws: a failure only leaves the invoice in the outbox.
  Future<void> onInvoiceCreated(int invoiceId) async {
    try {
      final entries = await _outbox.load();
      if (!entries.any((entry) => entry.invoiceId == invoiceId)) {
        await _outbox.save(<OutboxEntry>[
          ...entries,
          OutboxEntry(invoiceId: invoiceId),
        ]);
      }
      await flush();
    } on AppException {
      // The invoice stays queued; the next flush retries it.
    }
  }

  /// Tries every queued invoice on the channels that are still missing.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final settings = await _settingsStore.load();
      final entries = await _outbox.load();
      final kept = <OutboxEntry>[];
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final details = await _invoices.getDetails(entry.invoiceId);
        if (details == null) continue; // The invoice no longer exists.

        // Telegram is handled by the SyncCoordinator (PDF + database snapshot),
        // so this queue only tracks the computer from now on.
        const telegramDone = true;

        var desktopDone = entry.desktopDone || !settings.hasDesktop;
        if (!desktopDone) {
          try {
            await _bridge.pushInvoice(
              settings,
              InvoiceSyncPayload.toJson(
                details: details,
                deviceId: settings.deviceId,
                sentAt: _clock(),
              ),
            );
            desktopDone = true;
          } on SyncException {
            desktopDone = false;
          }
        }

        final next = OutboxEntry(
          invoiceId: entry.invoiceId,
          telegramDone: telegramDone,
          desktopDone: desktopDone,
        );
        if (!next.isDone) kept.add(next);
        // Save after every invoice so a phone that dies mid-flush keeps the
        // progress (and never sends the same Telegram message twice).
        await _outbox.save(<OutboxEntry>[...kept, ...entries.skip(i + 1)]);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<BridgeInfo> ping() async {
    final settings = await _settingsStore.load();
    if (settings.host.trim().isEmpty) {
      throw const SyncException('أدخل عنوان (IP) الكمبيوتر أولاً.');
    }
    return _bridge.ping(settings);
  }

  /// Takes a copy of the phone database and stores it on the computer.
  Future<BackupFile> sendBackupToDesktop() async {
    final settings = await _settingsStore.load();
    if (settings.host.trim().isEmpty) {
      throw const SyncException('أدخل عنوان (IP) الكمبيوتر أولاً.');
    }
    final backup = await _backups.createBackup();
    await _bridge.uploadDatabase(settings, backup.file);
    return backup;
  }

  /// Downloads the computer database and makes it the phone data.
  ///
  /// The file is validated and the current phone data is saved as a backup
  /// first, so a wrong file can always be undone from the backups list.
  Future<File> extractFromDesktop() async {
    final settings = await _settingsStore.load();
    if (settings.host.trim().isEmpty) {
      throw const SyncException('أدخل عنوان (IP) الكمبيوتر أولاً.');
    }
    final folder = await _backupsDirectory();
    final target = File(
      p.join(folder.path, 'desktop_extract_${AppDates.fileStamp(_clock())}.db'),
    );
    await _bridge.downloadDatabase(settings, target);
    await _backups.restore(target);
    return target;
  }

  /// The size of the phone database, for the information line in the screen.
  Future<int> localDatabaseBytes() async {
    final file = File(_database.path);
    return file.existsSync() ? file.length() : 0;
  }
}
