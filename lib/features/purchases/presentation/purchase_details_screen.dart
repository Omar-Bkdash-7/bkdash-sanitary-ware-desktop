import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/purchase_details_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One purchase bought from a customer, with its lines and payments.
class PurchaseDetailsScreen extends StatelessWidget {
  const PurchaseDetailsScreen({super.key, required this.purchaseId});

  final int purchaseId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PurchaseDetailsController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return PurchaseDetailsController(
          purchaseId: purchaseId,
          repository: deps.purchases,
          changes: deps.changes,
        )..load();
      },
      child: const _PurchaseDetailsView(),
    );
  }
}

class _PurchaseDetailsView extends StatelessWidget {
  const _PurchaseDetailsView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PurchaseDetailsController>();
    final details = controller.details;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          details == null ? 'عملية الشراء' : 'شراء #${details.purchase.id}',
        ),
        actions: [
          if (details != null)
            IconButton(
              tooltip: 'حذف عملية الشراء',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () =>
                  _delete(context, controller, details.purchase.id),
            ),
        ],
      ),
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => details == null
            ? const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'عملية الشراء غير موجودة',
              )
            : _PurchaseView(details: details),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    PurchaseDetailsController controller,
    int id,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف عملية الشراء #$id',
      message:
          'ستُحذف العملية نهائياً: تعود كميات الأصناف التي اشتريناها إلى ما '
          'كانت عليه، وتُلغى دفعة الشراء. لا يمكن الحذف إذا بيع من هذه '
          'الكميات أو دُفع للزبون لاحقاً.',
      confirmLabel: 'حذف العملية',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final navigator = Navigator.of(context);
    final deleted = await runUiAction(
      context,
      controller.deletePurchase,
      successMessage: 'حُذفت عملية الشراء وعاد المخزون كما كان',
    );
    if (deleted) navigator.pop();
  }
}

class _PurchaseView extends StatelessWidget {
  const _PurchaseView({required this.details});

  final PurchaseDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final purchase = details.purchase;
    final created = AppDates.tryParse(purchase.createdAt);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'الزبون', value: purchase.customerName),
                if (purchase.customerPhone.isNotEmpty)
                  _InfoRow(
                    label: 'الهاتف',
                    value: purchase.customerPhone,
                    ltr: true,
                  ),
                _InfoRow(
                  label: 'التاريخ',
                  value: created == null
                      ? purchase.purchaseDate
                      : '${AppDates.displayWithWeekday(created)}  '
                            '${AppDates.time12(created)}',
                ),
                if (purchase.notes.isNotEmpty)
                  _InfoRow(label: 'ملاحظات', value: purchase.notes),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('الأصناف', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < details.lines.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _LineTile(line: details.lines[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _AmountRow(
                  label: 'الإجمالي',
                  amount: purchase.total,
                  bold: true,
                ),
                _AmountRow(
                  label: 'المدفوع',
                  amount: purchase.paid,
                  color: scheme.success,
                ),
                _AmountRow(
                  label: 'المتبقي للزبون',
                  amount: purchase.remaining,
                  color: purchase.isSettled ? null : scheme.primary,
                ),
              ],
            ),
          ),
        ),
        if (details.payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('الدفعات', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < details.payments.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      details.payments[i].isLaterPayment
                          ? Icons.savings_outlined
                          : Icons.payments_outlined,
                      color: scheme.primary,
                    ),
                    title: Text(
                      details.payments[i].isLaterPayment
                          ? 'دفعة لاحقة'
                          : 'دفعة عند الشراء',
                    ),
                    subtitle: Text(
                      '${AppDates.displayIso(details.payments[i].paidAt)}  '
                      '${AppDates.timeIso(details.payments[i].paidAt)}',
                    ),
                    trailing: MoneyText(
                      details.payments[i].amount,
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.ltr = false});

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, textDirection: ltr ? TextDirection.ltr : null),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.color,
    this.bold = false,
  });

  final String label;
  final Money amount;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          MoneyText(
            amount,
            color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            style: bold ? Theme.of(context).textTheme.titleMedium : null,
          ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});

  final PurchaseLineRecord line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.itemName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${line.quantity} ${line.unit} × ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    MoneyText(
                      line.unitCost,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '  •  ${line.category}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          MoneyText(line.lineTotal, fontWeight: FontWeight.bold),
        ],
      ),
    );
  }
}
