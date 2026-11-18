/// The colour theme chosen by the user.
enum AppThemeMode {
  system('system', 'حسب النظام'),
  light('light', 'فاتح'),
  dark('dark', 'داكن');

  const AppThemeMode(this.key, this.label);

  final String key;
  final String label;

  static AppThemeMode fromKey(String? key) => AppThemeMode.values.firstWhere(
    (mode) => mode.key == key,
    orElse: () => AppThemeMode.system,
  );
}
