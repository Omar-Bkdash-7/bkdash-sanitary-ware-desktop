import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/bkdash_logo.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_file_sharer.dart';
import 'package:bkdash_sanitary_ware/features/backup/presentation/data_tools_screen.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/change_pin_dialog.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:bkdash_sanitary_ware/features/settings/models/app_theme_mode.dart';
import 'package:bkdash_sanitary_ware/features/settings/presentation/settings_controller.dart';
import 'package:bkdash_sanitary_ware/features/telegram/presentation/telegram_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// Appearance, security, data tools, Telegram and information about the
/// company. (The desktop twin of the phone's settings screen: no fingerprint,
/// no Wi-Fi bridge, plus where the files are kept.)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final paths = context.read<AppDependencies>().paths;
    final theme = Theme.of(context);
    final documents = p.dirname(paths.backups.path);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Section(
          title: 'المظهر',
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final mode in AppThemeMode.values)
                      ButtonSegment<AppThemeMode>(
                        value: mode,
                        label: Text(mode.label),
                      ),
                  ],
                  selected: <AppThemeMode>{settings.themeMode},
                  onSelectionChanged: (selection) =>
                      settings.setThemeMode(selection.first),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'الأمان',
          children: [
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('تغيير رمز PIN'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => _changePin(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('قفل البرنامج الآن'),
              subtitle: const Text('اختصار لوحة المفاتيح: Ctrl+L'),
              onTap: context.read<SecurityController>().lock,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'البيانات',
          children: [
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('النسخ الاحتياطي والتصدير'),
              subtitle: const Text('نسخة احتياطية، استعادة، تصدير إلى Excel'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DataToolsScreen(),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('فتح مجلد الملفات'),
              subtitle: Text(
                documents,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
              onTap: () => const SystemFileLauncher().open(documents),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('مكان قاعدة البيانات'),
              subtitle: SelectableText(
                paths.data.path,
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'الربط والمزامنة',
          children: [
            ListTile(
              leading: const Icon(Icons.send_rounded),
              title: const Text('إعدادات تيليجرام'),
              subtitle: const Text(
                'الفاتورة PDF ونسخة قاعدة البيانات إلى محادثتك الخاصة، '
                'واستيراد نسخة الهاتف',
              ),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TelegramSettingsScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'عن البرنامج',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BkdashLogo(isDark: theme.brightness == Brightness.dark),
                  const SizedBox(height: 12),
                  Text(
                    AppConstants.companyName,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(AppConstants.companyAddress)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        AppConstants.companyPhones.join('  -  '),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'الإصدار ${AppConstants.appVersion} - نسخة سطح المكتب',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const ChangePinDialog(),
    );
    if (changed == true && context.mounted) {
      showAppSnackBar(context, 'تم تغيير رمز PIN');
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}
