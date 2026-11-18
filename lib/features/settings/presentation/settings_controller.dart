import 'package:bkdash_sanitary_ware/features/settings/data/settings_repository.dart';
import 'package:bkdash_sanitary_ware/features/settings/models/app_theme_mode.dart';
import 'package:flutter/foundation.dart';

/// Holds the user preferences that affect the whole app (the theme).
class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);

  final SettingsRepository _repository;

  AppThemeMode _themeMode = AppThemeMode.system;
  bool _disposed = false;

  AppThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    _themeMode = await _repository.themeMode();
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _repository.setThemeMode(mode);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
