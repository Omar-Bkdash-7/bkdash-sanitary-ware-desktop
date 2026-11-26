import 'dart:async';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_caption.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_queue_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_retry.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_settings_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/backup_caption.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/sync_job.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Reads one saved invoice (the PDF is rendered at send time, not at save time).
typedef InvoiceDetailsLoader = Future<InvoiceDetails?> Function(int invoiceId);

/// Renders the invoice PDF into a temporary file.
typedef InvoicePdfBuilder = Future<File> Function(InvoiceDetails details);

/// Builds a checked snapshot of the live database.
typedef DatabaseSnapshotBuilder = Future<BackupFile> Function();

/// Reads the record counts printed in the snapshot caption.
typedef DatabaseSummaryLoader = Future<DataSummary> Function();

/// The single place that turns a saved change into a Telegram delivery.
///
/// Repositories report the write right after their transaction commits; this
/// class then
/// * queues the invoice PDF and uploads it immediately, and
/// * waits [snapshotDebounce] after the last change before building one
///   database snapshot, so a burst of edits produces a single upload.
///
/// Nothing here can break the sale: the caller never awaits a delivery, and
/// every failure is stored in the queue for a later retry.
class SyncCoordinator {
  SyncCoordinator({
    required SyncQueueStore queue,
    required TelegramSettingsStore settings,
    required TelegramService telegram,
    required KeyValueStore preferences,
    required DataChangeNotifier changes,
    required InvoiceDetailsLoader loadInvoice,
    required InvoicePdfBuilder buildPdf,
    required DatabaseSnapshotBuilder buildSnapshot,
    required DatabaseSummaryLoader loadSummary,
    required Clock clock,
    PublicBackupService? publicBackups,
    this.snapshotDebounce = defaultSnapshotDebounce,
    this.retryInterval = defaultRetryInterval,
  }) : _publicBackups = publicBackups,
       _queue = queue,
       _settings = settings,
       _telegram = telegram,
       _preferences = preferences,
       _changes = changes,
       _loadInvoice = loadInvoice,
       _buildPdf = buildPdf,
       _buildSnapshot = buildSnapshot,
       _loadSummary = loadSummary,
       _clock = clock;

  /// One constant for the whole feature: how long a burst of changes waits.
  static const Duration defaultSnapshotDebounce = Duration(seconds: 30);

  static const Duration defaultRetryInterval = Duration(minutes: 1);

  /// Set while a snapshot is still owed (survives the app being killed).
  static const String dirtyKey = 'sync.snapshot_dirty';

  final SyncQueueStore _queue;
  final TelegramSettingsStore _settings;
  final TelegramService _telegram;
  final KeyValueStore _preferences;
  final DataChangeNotifier _changes;
  final InvoiceDetailsLoader _loadInvoice;
  final InvoicePdfBuilder _buildPdf;
  final DatabaseSnapshotBuilder _buildSnapshot;
  final DatabaseSummaryLoader _loadSummary;
  final Clock _clock;

  final PublicBackupService? _publicBackups;

  final Duration snapshotDebounce;
  final Duration retryInterval;

  /// How many deliveries still wait, for the small status icon.
  final ValueNotifier<int> pending = ValueNotifier<int>(0);

  Timer? _debounce;
  Timer? _retryTimer;
  Future<void>? _draining;
  bool _rerun = false;
  bool _attached = false;

  /// Registers for write reports and retries what a previous run left behind.
  Future<void> start() async {
    _attach();
    if (await _isDirty()) {
      // The app was closed during the debounce window: send the snapshot now.
      await _enqueueSnapshot();
    }
    await flush();
    await _queue.pruneSent();
    _retryTimer ??= Timer.periodic(retryInterval, (_) => unawaited(flush()));
    await _refreshPending();
  }

  void dispose() {
    _changes.removeWriteListener(_onWrite);
    _attached = false;
    _debounce?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Tries every due delivery now (the manual retry button).
  Future<void> retryNow() async {
    await _queue.resetRetries(now: _clock());
    await flush();
  }

  /// Sends everything that is due; used at start-up and by the timer.
  ///
  /// A call made while a pass is already sending does not just return: it asks
  /// the running pass for another round. A job queued during a slow upload is
  /// therefore delivered by that drain, instead of waiting for
  /// [retryInterval], and an awaited call still means "everything due was
  /// tried".
  Future<void> flush() {
    final running = _draining;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final future = _drain();
    _draining = future;
    return future;
  }

  Future<void> _drain() async {
    try {
      do {
        _rerun = false;
        await _flushOnce();
      } while (_rerun);
    } finally {
      _draining = null;
      await _refreshPending();
    }
  }

  Future<void> _flushOnce() async {
    final settings = await _settings.load();
    if (!settings.isConfigured) return;
    final jobs = await _queue.due(now: _clock());
    var sent = false;
    for (final job in jobs) {
      if (!SyncRetry.canRetry(job.attempts)) {
        await _queue.markFailed(
          job.id,
          attempts: job.attempts,
          error: job.lastError.isEmpty
              ? 'تجاوز الإرسال عدد المحاولات المسموح.'
              : job.lastError,
        );
        continue;
      }
      sent = await _deliver(job, settings) || sent;
    }
    if (sent) await _queue.pruneSent();
  }

  /// `true` while a snapshot is still owed.
  Future<bool> _isDirty() async =>
      (await _preferences.getBool(dirtyKey)) ?? false;

  void _attach() {
    if (_attached) return;
    _attached = true;
    _changes.addWriteListener(_onWrite);
  }

  void _onWrite(DataWrite write, int? invoiceId) {
    unawaited(_handle(write, invoiceId));
  }

  Future<void> _handle(DataWrite write, int? invoiceId) async {
    try {
      switch (write) {
        case DataWrite.invoice:
        case DataWrite.invoiceUpdated:
          await _enqueueInvoice(invoiceId);
        case DataWrite.invoiceDeleted:
        case DataWrite.inventory:
        case DataWrite.customers:
        case DataWrite.payment:
        case DataWrite.purchase:
        case DataWrite.purchaseDeleted:
        case DataWrite.payout:
        case DataWrite.returnCreated:
        case DataWrite.returnDeleted:
          break;
      }
      await _scheduleSnapshot();
    } catch (_) {
      // Delivery problems must never surface as a failed sale.
    }
  }

  Future<void> _enqueueInvoice(int? invoiceId) async {
    if (invoiceId == null) return;
    final settings = await _settings.load();
    if (!settings.isConfigured || !settings.sendInvoicePdf) return;
    await _queue.add(
      kind: SyncJobKind.invoicePdf,
      createdAt: _clock(),
      invoiceId: invoiceId,
    );
    await _refreshPending();
    // The PDF goes out at once: the next sale may come in a second.
    unawaited(flush());
  }

  /// `true` while the public rolling copy also wants a fresh snapshot.
  Future<bool> _publicEnabled() async {
    final service = _publicBackups;
    if (service == null) return false;
    try {
      return await service.isEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Restarts the debounce window; one snapshot follows the last change.
  Future<void> _scheduleSnapshot() async {
    final settings = await _settings.load();
    final toTelegram = settings.isConfigured && settings.sendDatabase;
    if (!toTelegram && !await _publicEnabled()) return;
    await _preferences.setBool(dirtyKey, true);
    _debounce?.cancel();
    _debounce = Timer(snapshotDebounce, () => unawaited(_enqueueSnapshot()));
  }

  Future<void> _enqueueSnapshot() async {
    try {
      final settings = await _settings.load();
      final toTelegram = settings.isConfigured && settings.sendDatabase;
      final toPublic = await _publicEnabled();
      if (!toTelegram && !toPublic) {
        // Both destinations were switched off while the window was open.
        await _preferences.setBool(dirtyKey, false);
        return;
      }
      if (toTelegram) {
        // Only the newest snapshot is worth sending: drop the older ones.
        for (final job in await _queue.pendingOfKind(SyncJobKind.database)) {
          await _queue.remove(job.id);
          await _deleteFile(job.filePath);
        }
      }
      final snapshot = await _buildSnapshot();
      if (toPublic) {
        try {
          await _publicBackups!.keep(snapshot.file, fileName: snapshot.name);
        } catch (_) {
          // The public copy is a bonus; Telegram still gets its own upload.
        }
      }
      if (toTelegram) {
        final summary = await _loadSummary();
        await _queue.add(
          kind: SyncJobKind.database,
          createdAt: _clock(),
          filePath: snapshot.file.path,
          caption: BackupCaption.database(
            sentAt: _clock(),
            summary: summary,
            fileName: snapshot.name,
          ),
        );
      } else {
        await _deleteFile(snapshot.file.path);
      }
      await _preferences.setBool(dirtyKey, false);
      await _refreshPending();
      if (toTelegram) unawaited(flush());
    } catch (_) {
      // The dirty flag stays set, so the snapshot is tried again later.
    }
  }

  /// Returns `true` when the job reached Telegram.
  Future<bool> _deliver(SyncJob job, TelegramSettings settings) async {
    try {
      switch (job.kind) {
        case SyncJobKind.database:
          await _deliverSnapshot(job, settings);
        case SyncJobKind.invoicePdf:
          await _deliverInvoice(job, settings);
      }
      await _queue.markSent(job.id);
      return true;
    } on TelegramException catch (error) {
      await _queue.markRetry(
        job.id,
        attempts: job.attempts + 1,
        error: error.message,
        nextAttemptAt: _clock().add(
          error.retryAfter ?? SyncRetry.delayFor(job.attempts),
        ),
      );
      return false;
    } on AppException catch (error) {
      await _queue.markRetry(
        job.id,
        attempts: job.attempts + 1,
        error: error.message,
        nextAttemptAt: _clock().add(SyncRetry.delayFor(job.attempts)),
      );
      return false;
    } catch (error) {
      await _queue.markRetry(
        job.id,
        attempts: job.attempts + 1,
        error: 'تعذّر إرسال الملف: $error',
        nextAttemptAt: _clock().add(SyncRetry.delayFor(job.attempts)),
      );
      return false;
    }
  }

  Future<void> _deliverSnapshot(SyncJob job, TelegramSettings settings) async {
    final file = File(job.filePath);
    if (!file.existsSync()) return; // Nothing left to upload: nothing to retry.
    await _telegram.sendDocument(
      settings: settings,
      file: file,
      fileName: p.basename(job.filePath),
      caption: job.caption,
    );
    await _deleteFile(job.filePath);
  }

  Future<void> _deliverInvoice(SyncJob job, TelegramSettings settings) async {
    final invoiceId = job.invoiceId;
    if (invoiceId == null) return;
    final details = await _loadInvoice(invoiceId);
    if (details == null) return; // Deleted meanwhile: the snapshot covers it.
    final file = await _buildPdf(details);
    try {
      await _telegram.sendDocument(
        settings: settings,
        file: file,
        fileName: p.basename(file.path),
        contentType: 'application/pdf',
        caption: InvoiceCaption.build(details.invoice),
      );
    } finally {
      await _deleteFile(file.path);
    }
  }

  Future<void> _deleteFile(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // A leftover temporary file is harmless.
    }
  }

  Future<void> _refreshPending() async {
    pending.value = await _queue.pendingCount();
  }
}
