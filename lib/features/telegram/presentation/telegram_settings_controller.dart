import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/db_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_settings_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/backup_caption.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';
import 'package:flutter/foundation.dart';

/// The "Telegram settings" screen: the bot, the switches and a manual send.
class TelegramSettingsController extends BaseController {
  TelegramSettingsController({
    required TelegramSettingsStore settings,
    required TelegramService service,
    required DbSnapshotService snapshots,
    required BackupService backups,
    Clock? clock,
  }) : _settings = settings,
       _service = service,
       _snapshots = snapshots,
       _backups = backups,
       _clock = clock ?? DateTime.now;

  final TelegramSettingsStore _settings;
  final TelegramService _service;
  final DbSnapshotService _snapshots;
  final BackupService _backups;
  final Clock _clock;

  TelegramSettings _values = const TelegramSettings();
  String? _info;
  bool _busy = false;

  TelegramSettings get settings => _values;

  /// The last thing that happened, shown under the buttons.
  String? get info => _info;

  bool get isBusy => _busy;

  Future<void> load() => runLoad(() async {
    try {
      _values = await _settings.load();
    } catch (e, stackTrace) {
      debugPrint('Failed to load telegram settings: $e\n$stackTrace');
      _values = const TelegramSettings();
      throw SyncException('Failed to read saved settings. You can enter the data again.');
    }
  });

  Future<void> save(TelegramSettings settings) =>
      _guard(() => _store(settings, info: 'حُفظت إعدادات تيليجرام.'));

  Future<void> setSendInvoicePdf({required bool value}) =>
      _guard(() => _store(_values.copyWith(sendInvoicePdf: value)));

  Future<void> setSendDatabase({required bool value}) =>
      _guard(() => _store(_values.copyWith(sendDatabase: value)));

  /// Sends a test message; throws [TelegramException] with an Arabic reason.
  Future<void> testConnection() => _guard(() async {
    if (!_values.isConfigured) {
      throw const TelegramException(
        'أدخل رمز البوت ومعرّف المحادثة ثم احفظ قبل الاختبار.',
      );
    }
    await _service.sendMessage(
      settings: _values,
      text:
          '✅ تم ربط تطبيق بكداش بـ Telegram Desktop بنجاح.\n'
          'ستصل هنا فاتورة كل عملية بيع، ونسخ قاعدة البيانات.',
    );
    _info = 'وصلت رسالة تجريبية إلى Telegram.';
  });

  /// Builds a snapshot now and sends it, then deletes the temporary file.
  Future<void> sendSnapshotNow() => _guard(() async {
    if (!_values.isConfigured) {
      throw const TelegramException(
        'أدخل رمز البوت ومعرّف المحادثة ثم احفظ قبل الإرسال.',
      );
    }
    final snapshot = await _snapshots.create();
    try {
      final summary = await _backups.summarize();
      await _service.sendDocument(
        settings: _values,
        file: snapshot.file,
        fileName: snapshot.name,
        caption: BackupCaption.database(
          sentAt: _clock(),
          summary: summary,
          fileName: snapshot.name,
        ),
      );
    } finally {
      await _snapshots.dispose(snapshot);
    }
    _info = 'أُرسلت نسخة قاعدة البيانات إلى Telegram.';
  });

  Future<void> _store(TelegramSettings settings, {String? info}) async {
    await _settings.save(settings);
    _values = settings;
    _info = info;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    _busy = true;
    _info = null;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
