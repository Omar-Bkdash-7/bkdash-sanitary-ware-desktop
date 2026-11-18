import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/import_plan.dart';
import 'package:flutter/material.dart';

/// Shows what importing a database file would do and asks the owner to confirm.
///
/// Resolves to `true` only when the owner chose to import. When the file would
/// delete records that exist only on this computer, the import button stays
/// disabled until he ticks the box that says he understands.
Future<bool> showImportPlanDialog(
  BuildContext context,
  ImportPlan plan,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ImportPlanDialog(plan: plan),
  );
  return confirmed ?? false;
}

class _ImportPlanDialog extends StatefulWidget {
  const _ImportPlanDialog({required this.plan});

  final ImportPlan plan;

  @override
  State<_ImportPlanDialog> createState() => _ImportPlanDialogState();
}

class _ImportPlanDialogState extends State<_ImportPlanDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final scheme = Theme.of(context).colorScheme;
    final strong = plan.needsStrongWarning;
    final identical = plan.verdict == ImportVerdict.identical;
    final canImport = !identical && (!strong || _understood);

    return AlertDialog(
      title: Text(_title(plan.verdict)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Banner(
                message: _message(plan.verdict),
                color: strong
                    ? scheme.errorContainer
                    : scheme.secondaryContainer,
                onColor: strong
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
                icon: strong
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded,
              ),
              if (plan.fromThisComputer) ...[
                const SizedBox(height: 8),
                _Banner(
                  message:
                      'اسم الملف يدل على أنه صادر من هذا البرنامج نفسه وليس '
                      'من الهاتف. تأكد أنك اخترت ملف الهاتف.',
                  color: scheme.tertiaryContainer,
                  onColor: scheme.onTertiaryContainer,
                  icon: Icons.devices_other_rounded,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                plan.fileName,
                style: Theme.of(context).textTheme.bodySmall,
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 8),
              _CountsTable(plan: plan),
              if (plan.changed.total > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'سجلات موجودة في الجهازين ومحتواها مختلف: '
                  '${plan.changed.total} (يُعتمد ما في الملف).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'آخر عملية هنا: ${_activity(plan.localLastActivity)}\n'
                'آخر عملية في الملف: ${_activity(plan.incomingLastActivity)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                'قبل الاستبدال تُحفظ نسخة من بياناتك الحالية تلقائياً، وتجدها '
                'في «النسخ الاحتياطي» باسم before_restore.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (strong) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _understood,
                  onChanged: (value) =>
                      setState(() => _understood = value ?? false),
                  title: const Text(
                    'أفهم أن الاستيراد سيحذف من هذا الكمبيوتر ما ليس في الملف.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(identical ? 'إغلاق' : 'إلغاء'),
        ),
        if (!identical)
          FilledButton(
            style: strong
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: canImport ? () => Navigator.of(context).pop(true) : null,
            child: Text(strong ? 'استيراد واستبدال' : 'استيراد'),
          ),
      ],
    );
  }

  static String _title(ImportVerdict verdict) => switch (verdict) {
    ImportVerdict.identical => 'الملف مطابق لبياناتك',
    ImportVerdict.freshLocal => 'استيراد بيانات الهاتف',
    ImportVerdict.incomingNewer => 'نسخة أحدث من الهاتف',
    ImportVerdict.edited => 'نفس السجلات مع تعديلات',
    ImportVerdict.incomingOlder => 'تحذير: الملف أقدم من بياناتك',
    ImportVerdict.diverged => 'تحذير: تعديلات على الجهازين لم تُزامَن',
  };

  static String _message(ImportVerdict verdict) => switch (verdict) {
    ImportVerdict.identical =>
      'لا فرق بين الملف وما هو على هذا الكمبيوتر، فلا حاجة للاستيراد.',
    ImportVerdict.freshLocal =>
      'لا توجد على هذا الكمبيوتر فواتير أو زبائن بعد، فالاستيراد آمن ولن '
          'يضيع شيء.',
    ImportVerdict.incomingNewer =>
      'الملف يحتوي كل ما عندك وزيادة، وهذا هو الاستيراد الطبيعي بعد العمل '
          'على الهاتف.',
    ImportVerdict.edited =>
      'السجلات نفسها موجودة في الجهازين لكن بعضها مُعدَّل. سيُعتمد ما في '
          'الملف، وقد يكون تعديلك هنا هو الأحدث، فراجع الأرقام أدناه.',
    ImportVerdict.incomingOlder =>
      'الملف لا يحتوي بعض ما هو موجود هنا، فالاستيراد سيحذفه من هذا '
          'الكمبيوتر. غالباً هذا ملف قديم، أو سُجِّل شيء هنا بعد آخر مزامنة.',
    ImportVerdict.diverged =>
      'استُخدم الجهازان بعد آخر مزامنة: عندك سجلات ليست في الملف، وفي الملف '
          'سجلات ليست عندك. الاستيراد يُبقي ما في الملف ويحذف ما انفردت به '
          'هنا. الأسلم غالباً أن تُرسل نسخة هذا الكمبيوتر إلى الهاتف بدل أن '
          'تستورد، أو أن تعيد إدخال الفواتير الناقصة يدوياً بعد الاستيراد.',
  };

  static String _activity(String iso) {
    if (iso.isEmpty) return '—';
    return '${AppDates.displayIso(iso)} ${AppDates.timeIso(iso)}';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.onColor,
    required this.icon,
  });

  final String message;
  final Color color;
  final Color onColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: onColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: onColor)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountsTable extends StatelessWidget {
  const _CountsTable({required this.plan});

  final ImportPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final head = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget cell(String text, {TextStyle? style, bool start = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          text,
          style: style,
          textAlign: start ? TextAlign.start : TextAlign.center,
        ),
      );
    }

    TableRow row(String label, int now, int file, int lost, int gained) {
      return TableRow(
        children: [
          cell(label, start: true),
          cell('$now'),
          cell('$file'),
          cell(
            '$lost',
            style: lost > 0
                ? TextStyle(color: scheme.error, fontWeight: FontWeight.bold)
                : null,
          ),
          cell(
            '$gained',
            style: gained > 0
                ? TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)
                : null,
          ),
        ],
      );
    }

    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(2.2),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(1.3),
        4: FlexColumnWidth(1.3),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            cell(''),
            cell('هنا الآن', style: head),
            cell('في الملف', style: head),
            cell('سيُحذف', style: head),
            cell('سيُضاف', style: head),
          ],
        ),
        row(
          'الفواتير',
          plan.current.invoices,
          plan.incoming.invoices,
          plan.lost.invoices,
          plan.gained.invoices,
        ),
        row(
          'الزبائن',
          plan.current.customers,
          plan.incoming.customers,
          plan.lost.customers,
          plan.gained.customers,
        ),
        row(
          'الأصناف',
          plan.current.products,
          plan.incoming.products,
          plan.lost.items,
          plan.gained.items,
        ),
        row(
          'سندات القبض',
          plan.currentReceipts,
          plan.incomingReceipts,
          plan.lost.receipts,
          plan.gained.receipts,
        ),
      ],
    );
  }
}
