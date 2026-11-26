import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_caption.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/create_invoice_screen.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_details_controller.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';
import 'package:bkdash_sanitary_ware/features/returns/presentation/return_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One invoice in full: header, product lines, totals and payments.
class InvoiceDetailsScreen extends StatelessWidget {
  const InvoiceDetailsScreen({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InvoiceDetailsController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return InvoiceDetailsController(
          invoiceId: invoiceId,
          repository: deps.invoices,
          returns: deps.returns,
          changes: deps.changes,
        )..load();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('فاتورة #$invoiceId'),
          actions: [_InvoiceActions(invoiceId: invoiceId)],
        ),
        body: const _InvoiceDetailsBody(),
      ),
    );
  }
}

/// Edit and delete, the two ways an issued invoice can still change.
class _InvoiceActions extends StatelessWidget {
  const _InvoiceActions({required this.invoiceId});

  final int invoiceId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InvoiceDetailsController>();
    if (controller.status != LoadStatus.ready || controller.details == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'pdf':
            _sharePdf(context, controller);
          case 'return':
            _returnItems(context, controller);
          case 'edit':
            _edit(context);
          case 'delete':
            _delete(context, controller);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'pdf', child: Text('مشاركة الفاتورة PDF')),
        const PopupMenuItem(value: 'return', child: Text('إرجاع أصناف')),
        const PopupMenuItem(value: 'edit', child: Text('تعديل الفاتورة')),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'حذف الفاتورة',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  /// Builds the PDF of this invoice and opens the share sheet.
  Future<void> _sharePdf(
    BuildContext context,
    InvoiceDetailsController controller,
  ) async {
    final deps = context.read<AppDependencies>();
    await runUiAction(context, () async {
      final details = controller.details;
      if (details == null) return;
      final invoice = details.invoice;
      final previous = await deps.invoices.previousDebt(
        invoiceId: invoice.id,
        customerId: invoice.customerId,
      );
      final file = await deps.invoicePdf.create(
        details: details,
        previousDebt: previous,
      );
      await deps.sharer.shareFile(
        file,
        subject: 'فاتورة #${invoice.id}',
        text: InvoiceCaption.build(invoice),
      );
    });
  }

  /// Takes pieces back: the credit uses the prices of this invoice and the
  /// pieces return to the inventory row (and container) they came from.
  Future<void> _returnItems(
    BuildContext context,
    InvoiceDetailsController controller,
  ) async {
    final details = controller.details;
    if (details == null) return;
    final deps = context.read<AppDependencies>();
    final saved = await showReturnSheet(
      context,
      invoice: details.invoice,
      repository: deps.returns,
    );
    if (saved == true && context.mounted) {
      showAppSnackBar(context, 'تم تسجيل المرتجع وعادت الكميات إلى المخزون');
    }
  }

  Future<void> _edit(BuildContext context) async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => CreateInvoiceScreen(invoiceId: invoiceId),
      ),
    );
    if (id != null && context.mounted) {
      showAppSnackBar(context, 'تم حفظ تعديلات الفاتورة #$id');
    }
  }

  Future<void> _delete(
    BuildContext context,
    InvoiceDetailsController controller,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف الفاتورة #$invoiceId',
      message:
          'ستُحذف الفاتورة نهائياً: تعود كميات أصنافها إلى المخزون، وتُلغى '
          'دفعتها، ويعود حساب الزبون كما كان قبل إصدارها. لا يمكن التراجع.',
      confirmLabel: 'حذف الفاتورة',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final navigator = Navigator.of(context);
    final deleted = await runUiAction(
      context,
      controller.deleteInvoice,
      successMessage: 'حُذفت الفاتورة وعادت الكميات إلى المخزون',
    );
    if (deleted) navigator.pop();
  }
}

class _InvoiceDetailsBody extends StatelessWidget {
  const _InvoiceDetailsBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InvoiceDetailsController>();
    return LoadStateView(
      status: controller.status,
      errorMessage: controller.errorMessage,
      onRetry: controller.load,
      builder: (context) {
        final details = controller.details;
        if (details == null) {
          return const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'الفاتورة غير موجودة',
          );
        }
        return _InvoiceView(
          details: details,
          returns: controller.returns,
          returnedCredit: controller.returnedCredit,
          refunded: controller.refunded,
          remaining: controller.remainingAfterReturns,
        );
      },
    );
  }
}

class _InvoiceView extends StatelessWidget {
  const _InvoiceView({
    required this.details,
    required this.returns,
    required this.returnedCredit,
    required this.refunded,
    required this.remaining,
  });

  final InvoiceDetails details;
  final List<ReturnRecord> returns;
  final Money returnedCredit;
  final Money refunded;

  /// What is still owed after the returns.
  final Money remaining;

  Future<void> _deleteReturn(
    BuildContext context,
    ReturnRecord entry,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف المرتجع #${entry.id}',
      message:
          'ستُلغى قيمة المرتجع (${entry.total.format()}) من حساب الزبون، وتخرج '
          'الكميات من المخزون مرة أخرى. لا يمكن التراجع.',
      confirmLabel: 'حذف المرتجع',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = context.read<InvoiceDetailsController>();
    await runUiAction(
      context,
      () => controller.deleteReturn(entry.id),
      successMessage: 'حُذف المرتجع وأُعيد حساب الفاتورة',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final invoice = details.invoice;
    final created = AppDates.tryParse(invoice.createdAt);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'الزبون', value: invoice.customerName),
                if (invoice.customerPhone.isNotEmpty)
                  _InfoRow(
                    label: 'الهاتف',
                    value: invoice.customerPhone,
                    ltr: true,
                  ),
                _InfoRow(
                  label: 'التاريخ',
                  value: created == null
                      ? invoice.invoiceDate
                      : '${AppDates.displayWithWeekday(created)}  ${AppDates.time12(created)}',
                ),
                _InfoRow(
                  label: 'طريقة الدفع',
                  value: invoice.paymentMethod.label,
                ),
                if (invoice.notes.isNotEmpty)
                  _InfoRow(label: 'ملاحظات', value: invoice.notes),
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
                  amount: invoice.total,
                  bold: true,
                ),
                _AmountRow(
                  label: 'المدفوع',
                  amount: invoice.paid,
                  color: scheme.success,
                ),
                _AmountRow(
                  label: 'المتبقي',
                  amount: invoice.remaining,
                  color: invoice.isSettled ? null : scheme.error,
                ),
                const Divider(),
                _AmountRow(
                  label: 'ربح الفاتورة',
                  amount: invoice.profit,
                  color: scheme.info,
                ),
                if (returns.isNotEmpty) ...[
                  const Divider(),
                  _AmountRow(
                    label: 'قيمة المرتجعات',
                    amount: returnedCredit,
                    color: scheme.error,
                  ),
                  _AmountRow(
                    label: 'مُعاد نقداً',
                    amount: refunded,
                    color: scheme.info,
                  ),
                  _AmountRow(
                    label: 'المتبقي بعد المرتجعات',
                    amount: remaining,
                    color: remaining.isPositive ? scheme.error : scheme.success,
                    bold: true,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (returns.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('المرتجعات', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < returns.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ReturnTile(
                    entry: returns[i],
                    onDelete: () => _deleteReturn(context, returns[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
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
                      details.payments[i].isDebtPayment
                          ? Icons.savings_outlined
                          : Icons.payments_outlined,
                      color: scheme.success,
                    ),
                    title: Text(
                      details.payments[i].isDebtPayment
                          ? 'تسديد من الذمة'
                          : 'دفعة عند الإصدار',
                    ),
                    subtitle: Text(
                      '${AppDates.displayIso(details.payments[i].paidAt)}  '
                      '${AppDates.timeIso(details.payments[i].paidAt)}',
                    ),
                    trailing: MoneyText(
                      details.payments[i].amount,
                      color: scheme.success,
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

  final InvoiceLineRecord line;

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
                      line.unitPrice,
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

class _ReturnTile extends StatelessWidget {
  const _ReturnTile({required this.entry, required this.onDelete});

  final ReturnRecord entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pieces = entry.lines.fold<int>(0, (sum, line) => sum + line.quantity);
    return ListTile(
      leading: Icon(Icons.assignment_return_outlined, color: scheme.error),
      title: Text('مرتجع #${entry.id}  •  ${entry.total.format()}'),
      subtitle: Text(
        '${AppDates.displayIso(entry.returnDate)}  •  $pieces قطعة'
        '${entry.refund.isPositive ? '  •  أُعيد نقداً ${entry.refund.format()}' : ''}'
        '${entry.notes.isNotEmpty ? '\n${entry.notes}' : ''}',
      ),
      isThreeLine: entry.notes.isNotEmpty,
      trailing: IconButton(
        tooltip: 'حذف المرتجع',
        icon: const Icon(Icons.undo_rounded),
        onPressed: onDelete,
      ),
    );
  }
}
