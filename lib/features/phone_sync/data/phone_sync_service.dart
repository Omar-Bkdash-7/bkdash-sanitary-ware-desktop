import 'dart:convert';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/db_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/db_keys_reader.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/import_planner.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/telegram_inbox_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/import_plan.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/phone_sync_state.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_settings_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/backup_caption.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// A database file that was checked and compared, and is waiting for the owner
/// to confirm the import.
final class PreparedImport {
  const PreparedImport({required this.file, required this.plan, this.source});

  final File file;
  final ImportPlan plan;

  /// The Telegram message the file came from; `null` for a file picked by hand.
  final InboxDocument? source;
}

/// Moves the whole database between this computer and the phone, through the
/// owner's Telegram bot.
///
/// * **To the phone**: [sendSnapshotNow] uploads a consistent copy of the
///   database. (After every invoice or other change the shared
///   `SyncCoordinator` does the same on its own, with the invoice PDF.)
/// * **From the phone**: the phone already uploads its database after every
///   change. [fetchLatestFromTelegram] downloads the copy the owner forwarded to
///   the bot and [prepareFromFile] accepts a file picked by hand; both return a
///   [PreparedImport] whose [ImportPlan] says whether importing it is safe.
///   [applyImport] then replaces the data, after the restore service has taken a
///   safety copy of the current data.
class PhoneSyncService {
  PhoneSyncService({
    required AppDatabase database,
    required BackupService backups,
    required DbSnapshotService snapshots,
    required TelegramService telegram,
    required TelegramInboxService inbox,
    required TelegramSettingsStore settings,
    required KeyValueStore preferences,
    required Future<Directory> Function() receivedDirectory,
    required DatabaseFactory factory,
    Clock? clock,
  }) : _database = database,
       _backups = backups,
       _snapshots = snapshots,
       _telegram = telegram,
       _inbox = inbox,
       _settings = settings,
       _preferences = preferences,
       _received = receivedDirectory,
       _factory = factory,
       _clock = clock ?? DateTime.now;

  static const String lastImportKey = 'phone_sync.last_import';
  static const String lastExportKey = 'phone_sync.last_export';

  final AppDatabase _database;
  final BackupService _backups;
  final DbSnapshotService _snapshots;
  final TelegramService _telegram;
  final TelegramInboxService _inbox;
  final TelegramSettingsStore _settings;
  final KeyValueStore _preferences;
  final Future<Directory> Function() _received;
  final DatabaseFactory _factory;
  final Clock _clock;

  Future<bool> isTelegramConfigured() async =>
      (await _settings.load()).isConfigured;

  Future<DataSummary> currentSummary() => _backups.summarize();

  Future<PhoneSyncState> loadState() async => PhoneSyncState(
    lastImport: await _readEvent(lastImportKey),
    lastExport: await _readEvent(lastExportKey),
  );

  /// Uploads a consistent copy of the whole database to the owner's chat.
  Future<SyncEvent> sendSnapshotNow() async {
    final settings = await _settings.load();
    if (!settings.isConfigured) {
      throw const TelegramException(
        'أدخل رمز البوت ومعرّف المحادثة في «إعدادات تيليجرام» أولاً.',
      );
    }
    final snapshot = await _snapshots.create();
    try {
      final summary = await _backups.summarize();
      final sentAt = _clock();
      await _telegram.sendDocument(
        settings: settings,
        file: snapshot.file,
        fileName: snapshot.name,
        caption: BackupCaption.database(
          sentAt: sentAt,
          summary: summary,
          fileName: snapshot.name,
        ),
      );
      final event = SyncEvent(
        at: sentAt,
        fileName: snapshot.name,
        invoices: summary.invoices,
        customers: summary.customers,
        products: summary.products,
      );
      await _writeEvent(lastExportKey, event);
      return event;
    } finally {
      await _snapshots.dispose(snapshot);
    }
  }

  /// Downloads the newest database copy waiting in the chat with the bot, or
  /// `null` when there is none.
  Future<PreparedImport?> fetchLatestFromTelegram() async {
    final settings = await _settings.load();
    final documents = await _inbox.listDocuments(settings);
    if (documents.isEmpty) return null;
    // A copy this program uploaded itself is never news: prefer the phone's.
    final newest = documents.firstWhere(
      (document) => !document.isFromThisComputer,
      orElse: () => documents.first,
    );
    final file = await _inbox.download(
      settings,
      newest,
      folder: await _received(),
    );
    return prepareFromFile(file, source: newest);
  }

  /// Checks [file] (it must be a complete, healthy Bkdash database) and compares
  /// it with the data here. Nothing is changed.
  Future<PreparedImport> prepareFromFile(
    File file, {
    InboxDocument? source,
  }) async {
    final incomingSummary = await _backups.summarizeIncoming(file);
    final currentSummary = await _backups.summarize();
    final local = await DbKeysReader.read(_database.db);
    final incoming = await DbKeysReader.readFile(file, factory: _factory);
    final sourceName = source?.fileName ?? '';
    final name = sourceName.isNotEmpty ? sourceName : p.basename(file.path);
    final plan = ImportPlanner.compare(
      local: local,
      incoming: incoming,
      current: currentSummary,
      incomingSummary: incomingSummary,
      fileName: name,
      meta: source?.meta,
      fromThisComputer: name.startsWith(DesktopSnapshotService.filePrefix),
    );
    return PreparedImport(file: file, plan: plan, source: source);
  }

  /// Replaces all data here with the prepared file. The restore service keeps a
  /// safety copy of the current data first (`before_restore_*.db`).
  Future<void> applyImport(PreparedImport prepared) async {
    await _backups.restore(prepared.file);
    final plan = prepared.plan;
    await _writeEvent(
      lastImportKey,
      SyncEvent(
        at: _clock(),
        fileName: plan.fileName,
        invoices: plan.incoming.invoices,
        customers: plan.incoming.customers,
        products: plan.incoming.products,
        note: plan.verdict.name,
      ),
    );
    final source = prepared.source;
    if (source != null) {
      try {
        await _inbox.acknowledge(await _settings.load(), source.updateId);
      } on AppException {
        // Only housekeeping: the import itself already succeeded.
      }
    }
  }

  Future<SyncEvent?> _readEvent(String key) async {
    final raw = await _preferences.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? SyncEvent.fromJson(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeEvent(String key, SyncEvent event) =>
      _preferences.setString(key, jsonEncode(event.toJson()));
}
