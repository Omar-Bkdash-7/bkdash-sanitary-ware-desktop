import 'dart:io';

import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/public_backup_service.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/backup_file.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/restore_preview.dart';
import 'package:bkdash_sanitary_ware/features/backup/presentation/data_tools_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Backup, restore and export of the shop data.
class DataToolsScreen extends StatelessWidget {
  const DataToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DataToolsController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return DataToolsController(
          backups: deps.backups,
          exports: deps.exports,
          picker: deps.picker,
          sharer: deps.sharer,
          publicBackups: deps.publicBackups,
        )..load();
      },
      child: const _DataToolsView(),
    );
  }
}

class _DataToolsView extends StatelessWidget {
  const _DataToolsView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DataToolsController>();
    final theme = Theme.of(context);
    final busy = controller.isBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي والتصدير'),
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Block(
            title: 'النسخ الاحتياطي',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'تُحفظ النسخة في مجلد المستندات\\Bkdash\\backups، ويمكنك نسخها إلى قرص خارجي أو سحابة '
                  'لتبقى محفوظة خارج الجهاز.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => _backup(context, controller, share: true),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('إنشاء نسخة وإظهارها في المجلد'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _backup(context, controller, share: false),
                      icon: const Icon(Icons.save_alt_rounded),
                      label: const Text('إنشاء نسخة داخل المجلد فقط'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Block(
            title: 'نسخ تلقائية تبقى بعد حذف التطبيق',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.folder_copy_outlined),
                title: const Text('حفظ نسخة تلقائية بعد كل تعديل'),
                subtitle: Text(
                  controller.publicSupported
                      ? 'يُحفظ آخر ${PublicBackupService.keepLast} نسخ في مجلد المستندات\\Bkdash\\AutoBackups '
                            'بعد كل تعديل. '
                            'المحفوظ الآن: ${controller.publicCopies.length}'
                      : 'غير متاح على هذا الإصدار من أندرويد '
                            '(يتطلب أندرويد 10 أو أحدث).',
                ),
                value: controller.publicEnabled,
                onChanged: controller.publicSupported && !busy
                    ? (value) => runUiAction(
                        context,
                        () => controller.setPublicBackups(enabled: value),
                        successMessage: value
                            ? 'ستُحفظ نسخة تلقائية بعد كل تعديل'
                            : 'أُوقف النسخ التلقائي',
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Block(
            title: 'الاستعادة',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'تستبدل الاستعادة كل البيانات الحالية ببيانات النسخة. '
                  'تُحفظ نسخة من بياناتك الحالية قبل الاستبدال.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _restoreFromFile(context, controller),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('استعادة من ملف...'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Block(
            title: 'النسخ المحفوظة على الكمبيوتر (${controller.backups.length})',
            children: [
              if (controller.backups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد نسخ محفوظة بعد.'),
                )
              else
                for (final backup in controller.backups)
                  _BackupTile(
                    backup: backup,
                    enabled: !busy,
                    onShare: () =>
                        runUiAction(context, () => controller.share(backup)),
                    onRestore: () =>
                        _confirmRestore(context, controller, backup.file),
                    onDelete: () => _delete(context, controller, backup),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          _Block(
            title: 'التصدير إلى Excel (CSV)',
            children: [
              for (final kind in ExportKind.values)
                ListTile(
                  enabled: !busy,
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(kind.label),
                  trailing: const Icon(Icons.ios_share_rounded),
                  onTap: () =>
                      runUiAction(context, () => controller.export(kind)),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _backup(
    BuildContext context,
    DataToolsController controller, {
    required bool share,
  }) {
    return runUiAction(context, () async {
      final backup = await controller.createBackup();
      if (share) await controller.share(backup);
    }, successMessage: share ? null : 'تم إنشاء النسخة الاحتياطية');
  }

  Future<void> _restoreFromFile(
    BuildContext context,
    DataToolsController controller,
  ) async {
    File? picked;
    final ok = await runUiAction(context, () async {
      picked = await controller.pickBackupFile();
    });
    final file = picked;
    if (!ok || file == null || !context.mounted) return;
    await _confirmRestore(context, controller, file);
  }

  /// Checks the file, then shows what replaces what before anything changes.
  Future<void> _confirmRestore(
    BuildContext context,
    DataToolsController controller,
    File file,
  ) async {
    RestorePreview? preview;
    final checked = await runUiAction(context, () async {
      preview = await controller.previewRestore(file);
    });
    final ready = preview;
    if (!checked || ready == null || !context.mounted) return;
    final confirmed = await _showRestoreDialog(context, ready);
    if (!confirmed || !context.mounted) return;
    await runUiAction(
      context,
      () => controller.restore(file),
      successMessage: 'تمت استعادة البيانات بنجاح',
    );
  }

  /// The overwrite warning, with the counts of the current and the incoming
  /// data so the choice is made on facts, not on a guess.
  Future<bool> _showRestoreDialog(
    BuildContext context,
    RestorePreview preview,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ستُستبدل كل البيانات الحالية (المخزون والزبائن '
                'والفواتير) ببيانات النسخة المحددة:',
              ),
              const SizedBox(height: 14),
              _CountRow(
                label: 'الفواتير',
                current: preview.current.invoices,
                incoming: preview.incoming.invoices,
              ),
              _CountRow(
                label: 'الزبائن',
                current: preview.current.customers,
                incoming: preview.incoming.customers,
              ),
              _CountRow(
                label: 'الأصناف',
                current: preview.current.products,
                incoming: preview.incoming.products,
              ),
              const SizedBox(height: 14),
              Text(
                'تُحفظ نسخة من بياناتك الحالية تلقائياً قبل الاستبدال، '
                'فتستطيع الرجوع إليها من «النسخ المحفوظة على الكمبيوتر».',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استعادة واستبدال'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _delete(
    BuildContext context,
    DataToolsController controller,
    BackupFile backup,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف النسخة',
      message: 'هل تريد حذف "${backup.name}"؟',
      confirmLabel: AppStrings.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runUiAction(context, () => controller.delete(backup));
  }
}

/// "الفواتير: الحالي 12 ← النسخة 9".
class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.current,
    required this.incoming,
  });

  final String label;
  final int current;
  final int incoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = current != incoming;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$current  ←  $incoming',
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: changed ? FontWeight.bold : null,
                color: changed ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children});

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

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.backup,
    required this.enabled,
    required this.onShare,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupFile backup;
  final bool enabled;
  final VoidCallback onShare;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: const Icon(Icons.storage_rounded),
      title: Text(
        backup.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${AppDates.display(backup.modified)}  ${AppDates.time12(backup.modified)}'
        '  •  ${backup.sizeLabel}',
      ),
      trailing: PopupMenuButton<String>(
        enabled: enabled,
        onSelected: (value) {
          switch (value) {
            case 'share':
              onShare();
            case 'restore':
              onRestore();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'share', child: Text(AppStrings.share)),
          PopupMenuItem(value: 'restore', child: Text('استعادة')),
          PopupMenuItem(value: 'delete', child: Text(AppStrings.delete)),
        ],
      ),
    );
  }
}
