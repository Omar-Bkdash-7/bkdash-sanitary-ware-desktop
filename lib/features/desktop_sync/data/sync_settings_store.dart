import 'dart:convert';

import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/sync_settings.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_settings_store.dart';

/// Keeps [SyncSettings] in the phone preferences.
class SyncSettingsStore {
  SyncSettingsStore(this._store, {TelegramSettingsStore? telegram})
    : _telegram = telegram;

  final KeyValueStore _store;

  /// Used once, to move an old bot token out of the plain preferences.
  final TelegramSettingsStore? _telegram;

  static const String _key = 'sync.settings';

  /// Reads the settings; a phone that has no id yet gets one on the first call.
  Future<SyncSettings> load() async {
    final raw = await _store.getString(_key);
    var settings = const SyncSettings();
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw) as Map<String, Object?>;
        await _moveTelegramSecrets(json);
        settings = SyncSettings.fromJson(json);
      } on FormatException {
        // A damaged value is simply replaced by the defaults.
        settings = const SyncSettings();
      }
    }
    if (settings.deviceId.isEmpty) {
      settings = settings.copyWith(deviceId: SyncSettings.newDeviceId());
      await save(settings);
    }
    return settings;
  }

  Future<void> save(SyncSettings settings) =>
      _store.setString(_key, jsonEncode(settings.toJson()));

  /// Moves a bot token that older versions saved in plain text into the
  /// encrypted store, then rewrites the preferences without it.
  Future<void> _moveTelegramSecrets(Map<String, Object?> json) async {
    final telegram = _telegram;
    if (telegram == null) return;
    final hasLegacy =
        json.containsKey('telegramToken') ||
        json.containsKey('telegramChatId') ||
        json.containsKey('telegramEnabled');
    if (!hasLegacy) return;

    final token = ((json['telegramToken'] as String?) ?? '').trim();
    final chatId = ((json['telegramChatId'] as String?) ?? '').trim();
    final enabled = json['telegramEnabled'] == true;
    if ((token.isNotEmpty || chatId.isNotEmpty) && !await telegram.hasToken()) {
      final current = await telegram.load();
      await telegram.save(
        current.copyWith(
          token: token,
          chatId: chatId,
          sendInvoicePdf: enabled || current.sendInvoicePdf,
          sendDatabase: enabled || current.sendDatabase,
        ),
      );
    }

    json
      ..remove('telegramToken')
      ..remove('telegramChatId')
      ..remove('telegramEnabled');
    await _store.setString(_key, jsonEncode(json));
  }
}
