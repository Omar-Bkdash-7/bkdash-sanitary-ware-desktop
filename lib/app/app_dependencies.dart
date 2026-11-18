import 'dart:async';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/services/file_sharer.dart';
import 'package:bkdash_sanitary_ware/core/storage/flutter_secure_secret_store.dart';
import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/core/storage/secret_store.dart';
import 'package:bkdash_sanitary_ware/core/storage/shared_preferences_store.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_backup_picker.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_file_sharer.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_paths.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/folder_public_backup_storage.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/no_biometric_authenticator.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_file_picker.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/db_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/export_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_service.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/desktop_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_pdf_service.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/payment_repository.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/phone_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/telegram_inbox_service.dart';
import 'package:bkdash_sanitary_ware/features/reports/data/report_repository.dart';
import 'package:bkdash_sanitary_ware/features/security/data/biometric_authenticator.dart';
import 'package:bkdash_sanitary_ware/features/security/data/security_repository.dart';
import 'package:bkdash_sanitary_ware/features/settings/data/settings_repository.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_coordinator.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_queue_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_settings_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show DatabaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

/// Everything the screens need, created once when the program starts.
///
/// This is the desktop twin of the phone's `app_dependencies.dart`. The class
/// keeps the same name and the same members, so the screens copied from the
/// phone project work unchanged; what differs is which concrete classes are
/// plugged in (SQLite through FFI, files in folders instead of MediaStore and
/// the share sheet, no fingerprint, no LAN bridge).
final class AppDependencies {
  AppDependencies._({
    required this.paths,
    required this.database,
    required this.changes,
    required this.items,
    required this.customers,
    required this.invoices,
    required this.payments,
    required this.reports,
    required this.security,
    required this.settings,
    required this.biometrics,
    required this.backups,
    required this.snapshots,
    required this.publicBackups,
    required this.invoicePdf,
    required this.syncQueue,
    required this.syncCoordinator,
    required this.telegram,
    required this.telegramSettings,
    required this.phoneSync,
    required this.exports,
    required this.picker,
    required this.sharer,
  });

  /// Opens the database and builds every repository and service.
  static Future<AppDependencies> create({required DesktopPaths paths}) async {
    await paths.ensureCreated();
    final DatabaseFactory factory = databaseFactoryFfi;

    final database = await AppDatabase.open(
      factory: factory,
      directory: paths.data.path,
      migrationSafetyDirectory: () async =>
          Directory(p.join(paths.backups.path, 'before_upgrade')),
    );
    final changes = DataChangeNotifier();
    final KeyValueStore store = SharedPreferencesStore();
    final SecretStore secrets = FlutterSecureSecretStore();
    final telegramSettings = TelegramSettingsStore(secrets, store);
    final telegram = TelegramService();
    final invoicePdf = InvoicePdfService();

    final items = ItemRepository(database, changes);
    final customers = CustomerRepository(database, changes);
    final invoices = InvoiceRepository(database, changes);
    final payments = PaymentRepository(database, changes);

    final backups = BackupService(
      database: database,
      changes: changes,
      backupsDirectory: () async => paths.backups,
    );
    final snapshots = DesktopSnapshotService(
      database: database,
      snapshotDirectory: () async =>
          Directory(p.join(paths.temp.path, 'snapshots')),
      factory: factory,
    );
    final publicBackups = PublicBackupService(
      storage: FolderPublicBackupStorage(paths.autoCopies),
      preferences: store,
    );

    final syncQueue = await SqfliteSyncQueueStore.open(
      factory: factory,
      directory: paths.data.path,
    );
    final syncCoordinator = SyncCoordinator(
      queue: syncQueue,
      settings: telegramSettings,
      telegram: telegram,
      preferences: store,
      changes: changes,
      loadInvoice: invoices.getDetails,
      buildPdf: (details) async {
        final previous = await invoices.previousDebt(
          invoiceId: details.invoice.id,
          customerId: details.invoice.customerId,
        );
        return invoicePdf.create(details: details, previousDebt: previous);
      },
      buildSnapshot: snapshots.create,
      loadSummary: backups.summarize,
      clock: DateTime.now,
      publicBackups: publicBackups,
    );
    unawaited(syncCoordinator.start());

    final phoneSync = PhoneSyncService(
      database: database,
      backups: backups,
      snapshots: snapshots,
      telegram: telegram,
      inbox: TelegramInboxService(),
      settings: telegramSettings,
      preferences: store,
      receivedDirectory: () async => paths.received,
      factory: factory,
    );

    return AppDependencies._(
      paths: paths,
      database: database,
      changes: changes,
      items: items,
      customers: customers,
      invoices: invoices,
      payments: payments,
      reports: ReportRepository(database, invoices),
      security: SecurityRepository(store),
      settings: SettingsRepository(store),
      biometrics: const NoBiometricAuthenticator(),
      backups: backups,
      snapshots: snapshots,
      publicBackups: publicBackups,
      invoicePdf: invoicePdf,
      syncQueue: syncQueue,
      syncCoordinator: syncCoordinator,
      telegram: telegram,
      telegramSettings: telegramSettings,
      phoneSync: phoneSync,
      exports: ExportService(
        items: items,
        invoices: invoices,
        customers: customers,
        exportDirectory: () async => paths.exports,
      ),
      picker: DesktopBackupPicker(
        () async => Directory(p.join(paths.temp.path, 'picked')),
      ),
      sharer: DesktopFileSharer(folder: paths.exports),
    );
  }

  /// Where every file of the program lives.
  final DesktopPaths paths;

  final AppDatabase database;
  final DataChangeNotifier changes;
  final ItemRepository items;
  final CustomerRepository customers;
  final InvoiceRepository invoices;
  final PaymentRepository payments;
  final ReportRepository reports;
  final SecurityRepository security;
  final SettingsRepository settings;
  final BiometricAuthenticator biometrics;
  final BackupService backups;
  final DbSnapshotService snapshots;
  final PublicBackupService publicBackups;
  final InvoicePdfService invoicePdf;
  final SyncQueueStore syncQueue;
  final SyncCoordinator syncCoordinator;
  final TelegramService telegram;
  final TelegramSettingsStore telegramSettings;
  final PhoneSyncService phoneSync;
  final ExportService exports;
  final BackupFilePicker picker;
  final FileSharer sharer;

  /// The phone app can push invoices to a small Python program on the LAN. A
  /// computer running this program does not need it (Telegram replaces it), so
  /// the create-invoice screen, which accepts `null`, simply skips that step.
  DesktopSyncService? get sync => null;
}
