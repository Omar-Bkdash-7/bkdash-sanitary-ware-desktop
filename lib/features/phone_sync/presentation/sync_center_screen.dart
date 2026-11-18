import 'dart:io';

import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/phone_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/phone_sync_state.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/presentation/import_plan_dialog.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/presentation/sync_center_controller.dart';
import 'package:bkdash_sanitary_ware/features/telegram/presentation/sync_log_screen.dart';
import 'package:bkdash_sanitary_ware/features/telegram/presentation/telegram_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Moves the data between this computer and the phone, through Telegram.
class SyncCenterScreen extends StatelessWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncCenterController>();
    return LoadStateView(
      status: controller.status,
      errorMessage: controller.errorMessage,
      onRetry: controller.load,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.isBusy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (!controller.telegramReady) ...[
            const _NoticeCard(
              icon: Icons.link_off_rounded,
              title: 'اربط Telegram أولاً',
              message:
                  'أدخل رمز البوت ومعرّف المحادثة نفسيهما اللذين في تطبيق '
                  'الهاتف (إعدادات ← إعدادات تيليجرام). لا يمكن لهذا '
                  'الكمبيوتر أن يرسل أو يستقبل شيئاً قبل ذلك.',
              action: _OpenTelegramSettings(),
            ),
            const SizedBox(height: 12),
          ] else if (controller.looksUnused) ...[
            const _NoticeCard(
              icon: Icons.download_for_offline_rounded,
              title: 'ابدأ باستيراد بيانات الهاتف',
              message:
                  'هذا الكمبيوتر ما زال بلا فواتير ولا زبائن. قبل أن تسجل '
                  'أي شيء هنا، استورد بيانات الهاتف من «استيراد من الهاتف» '
                  'أدناه، حتى لا ينفصل الجهازان.',
            ),
            const SizedBox(height: 12),
          ],
          _StatusCard(controller: controller),
          const SizedBox(height: 12),
          _SendCard(controller: controller),
          const SizedBox(height: 12),
          _ReceiveCard(controller: controller),
          if (controller.info != null) ...[
            const SizedBox(height: 12),
            Text(
              controller.info!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const _RulesCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _OpenTelegramSettings extends StatelessWidget {
  const _OpenTelegramSettings();

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TelegramSettingsScreen()),
      ),
      icon: const Icon(Icons.send_rounded),
      label: const Text('إعدادات تيليجرام'),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.onTertiaryContainer, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(color: scheme.onTertiaryContainer),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 12),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final SyncCenterController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = controller.summary;
    final state = controller.state;
    final auto = controller.lastAutoSent;
    final coordinator = context.read<AppDependencies>().syncCoordinator;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  controller.telegramReady
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  color: controller.telegramReady
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.telegramReady
                        ? 'Telegram مرتبط'
                        : 'Telegram غير مرتبط',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TelegramSettingsScreen(),
                    ),
                  ),
                  child: const Text('الإعدادات'),
                ),
              ],
            ),
            const Divider(),
            if (summary != null)
              _Line(
                label: 'بيانات هذا الكمبيوتر الآن',
                value:
                    '${summary.invoices} فاتورة، ${summary.customers} زبون، '
                    '${summary.products} صنف',
              ),
            _Line(
              label: 'آخر نسخة أُرسلت تلقائياً',
              value: auto == null ? '—' : _stamp(auto),
            ),
            _Line(
              label: 'آخر نسخة أُرسلت يدوياً',
              value: _event(state.lastExport),
            ),
            _Line(
              label: 'آخر استيراد من الهاتف',
              value: _event(state.lastImport),
            ),
            ValueListenableBuilder<int>(
              valueListenable: coordinator.pending,
              builder: (context, pending, _) => Row(
                children: [
                  Expanded(
                    child: _Line(
                      label: 'بانتظار الإرسال إلى Telegram',
                      value: pending == 0 ? 'لا شيء' : '$pending',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SyncLogScreen(),
                      ),
                    ),
                    child: const Text('سجل الإرسال'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime at) =>
      '${AppDates.display(at)} ${AppDates.time12(at)}';

  static String _event(SyncEvent? event) {
    if (event == null) return '—';
    return '${_stamp(event.at)} (${event.invoices} فاتورة)';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _SendCard extends StatelessWidget {
  const _SendCard({required this.controller});

  final SyncCenterController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = controller.isBusy || !controller.telegramReady;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.upload_rounded),
                const SizedBox(width: 8),
                Text(
                  'إرسال بيانات الكمبيوتر إلى الهاتف',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'بعد كل فاتورة تصل الفاتورة PDF إلى Telegram فوراً للمراجعة، '
              'وتُرسل نسخة قاعدة البيانات بعد نصف دقيقة من آخر تعديل. '
              'ويمكنك إرسال نسخة كاملة الآن:',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: disabled ? null : () => _send(context),
              icon: const Icon(Icons.send_rounded),
              label: const Text('إرسال نسخة كاملة الآن'),
            ),
            const SizedBox(height: 16),
            Text('على الهاتف:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(
              '1. افتح Telegram وانتظر وصول ملف باسم bkdash_desktop_….db\n'
              '2. اضغط على الملف واحفظه في «التنزيلات».\n'
              '3. في تطبيق بكداش: الإعدادات ← النسخ الاحتياطي والتصدير ← '
              '«استعادة من ملف…» ثم اختر الملف.\n'
              '4. راجع أرقام المعاينة قبل التأكيد: عدد الفواتير في الملف '
              'يجب أن يساوي ما عند الهاتف أو يزيد عنه.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    await runUiAction(context, controller.sendNow);
  }
}

class _ReceiveCard extends StatelessWidget {
  const _ReceiveCard({required this.controller});

  final SyncCenterController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded),
                const SizedBox(width: 8),
                Text(
                  'استيراد من الهاتف',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'الهاتف يرسل نسخة قاعدة بياناته إلى Telegram بعد كل تعديل. '
              'ليراها هذا البرنامج: في Telegram اختر آخر ملف .db أرسله '
              'الهاتف واضغط «إعادة توجيه» (Forward) إلى محادثة البوت نفسه، '
              'ثم اضغط الزر الأول. ويمكنك بدلاً من ذلك حفظ الملف من '
              'Telegram واختياره بالزر الثاني.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: controller.isBusy || !controller.telegramReady
                      ? null
                      : () => _fetch(context),
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('جلب آخر نسخة من Telegram'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy ? null : () => _pick(context),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('اختيار ملف .db من الكمبيوتر'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'يسمح Telegram للبوتات بتنزيل ملفات حتى 20 ميغابايت فقط.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetch(BuildContext context) async {
    PreparedImport? prepared;
    final ok = await runUiAction(context, () async {
      prepared = await controller.fetchFromTelegram();
    });
    if (!context.mounted) return;
    final ready = prepared;
    if (ok && ready == null) {
      showAppSnackBar(
        context,
        'لا توجد نسخة بانتظارك في Telegram. أعد توجيه آخر ملف .db أرسله '
        'الهاتف إلى محادثة البوت ثم جرّب مرة أخرى.',
      );
      return;
    }
    if (ready != null) await _confirm(context, ready);
  }

  Future<void> _pick(BuildContext context) async {
    File? picked;
    final ok = await runUiAction(context, () async {
      picked = await context.read<AppDependencies>().picker.pickBackup();
    });
    final file = picked;
    if (!ok || file == null || !context.mounted) return;

    PreparedImport? prepared;
    final done = await runUiAction(context, () async {
      prepared = await controller.prepareFromFile(file);
    });
    final ready = prepared;
    if (!done || ready == null || !context.mounted) return;
    await _confirm(context, ready);
  }

  Future<void> _confirm(BuildContext context, PreparedImport prepared) async {
    final confirmed = await showImportPlanDialog(context, prepared.plan);
    if (!confirmed || !context.mounted) return;
    await runUiAction(
      context,
      () => controller.apply(prepared),
      successMessage: 'تم استيراد البيانات بنجاح',
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rule_rounded),
                const SizedBox(width: 8),
                Text(
                  'قاعدة العمل بين الجهازين',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'الاستيراد يستبدل كل البيانات بنسخة الملف، فاعمل بالتناوب:\n'
              '• قبل أن تبدأ على جهاز، استورد آخر نسخة من الجهاز الآخر.\n'
              '• وبعد أن تنتهي، أرسل نسخة جهازك (تلقائياً أو بالزر) '
              'واستوردها في الجهاز الآخر.\n'
              '• لا تسجّل فواتير على الجهازين قبل المزامنة: ستحمل الفاتورتان '
              'الرقم نفسه ولا يمكن دمجهما، وسيحذّرك البرنامج عند ذلك.\n'
              '• يحفظ البرنامج قبل كل استيراد نسخة من بياناتك الحالية، '
              'فلا يضيع شيء بخطأ واحد.',
            ),
          ],
        ),
      ),
    );
  }
}
