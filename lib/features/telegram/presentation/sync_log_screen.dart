import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/sync_job.dart';
import 'package:bkdash_sanitary_ware/features/telegram/presentation/sync_log_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The last 50 delivery attempts, with their error and a retry button.
class SyncLogScreen extends StatelessWidget {
  const SyncLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SyncLogController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return SyncLogController(
          queue: deps.syncQueue,
          coordinator: deps.syncCoordinator,
        )..load();
      },
      child: const _SyncLogView(),
    );
  }
}

class _SyncLogView extends StatelessWidget {
  const _SyncLogView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncLogController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الإرسال'),
        actions: [
          IconButton(
            tooltip: 'إعادة المحاولة الآن',
            onPressed: controller.isBusy
                ? null
                : () => runUiAction(
                    context,
                    controller.retryNow,
                    successMessage: 'حُدِّثت قائمة الإرسال',
                  ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: controller.isBusy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  controller.pending == 0
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  color: controller.pending == 0
                      ? theme.colorScheme.success
                      : theme.colorScheme.primary,
                ),
                title: Text(
                  controller.pending == 0
                      ? 'لا شيء بانتظار الإرسال'
                      : '${controller.pending} عنصر بانتظار الإرسال',
                ),
                subtitle: const Text(
                  'يُعاد الإرسال تلقائياً عند عودة الشبكة، أو فوراً بالزر أعلاه.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (controller.jobs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لم تُرسل أي ملفات بعد.'),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < controller.jobs.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _JobTile(job: controller.jobs[i]),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});

  final SyncJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, icon, color) = switch (job.status) {
      SyncJobStatus.sent => (
        'أُرسل',
        Icons.check_circle_outline_rounded,
        scheme.success,
      ),
      SyncJobStatus.pending => (
        'بالانتظار',
        Icons.schedule_rounded,
        scheme.warning,
      ),
      SyncJobStatus.failed => (
        'فشل',
        Icons.error_outline_rounded,
        scheme.error,
      ),
    };
    final title = job.kind == SyncJobKind.invoicePdf
        ? 'فاتورة #${job.invoiceId} (PDF)'
        : 'نسخة قاعدة البيانات';
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${AppDates.display(job.createdAt)}  ${AppDates.time12(job.createdAt)}'
            '${job.attempts > 0 ? '  •  محاولات: ${job.attempts}' : ''}',
          ),
          if (job.lastError.isNotEmpty)
            Text(
              job.lastError,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
        ],
      ),
      trailing: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
