import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/features/settings/models/app_theme_mode.dart';

/// Stores the user preferences.
class SettingsRepository {
  SettingsRepository(this._store);

  final KeyValueStore _store;

  static const String _themeKey = 'settings.theme_mode';

  Future<AppThemeMode> themeMode() async =>
      AppThemeMode.fromKey(await _store.getString(_themeKey));

  Future<void> setThemeMode(AppThemeMode mode) =>
      _store.setString(_themeKey, mode.key);
}
