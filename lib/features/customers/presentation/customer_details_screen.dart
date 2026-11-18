import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/core/widgets/stat_tile.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customer_details_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customer_form_sheet.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/receive_payment_sheet.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_card.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The account statement of one customer: totals, invoices and payments.
class CustomerDetailsScreen extends StatelessWidget {
  const CustomerDetailsScreen({super.key, required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CustomerDetailsController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return CustomerDetailsController(
          customerId: customerId,
          customers: deps.customers,
          invoices: deps.invoices,
          payments: deps.payments,
          changes: deps.changes,
        )..load();
      },
      child: const _CustomerDetailsView(),
    );
  }
}

class _CustomerDetailsView extends StatelessWidget {
  const _CustomerDetailsView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CustomerDetailsController>();
    final summary = controller.summary;
    return Scaffold(
      appBar: AppBar(
        title: Text(summary?.customer.name ?? 'الزبون'),
        actions: [
          if (summary != null)
            PopupMenuButton<String>(
              onSelected: (value) => value == 'edit'
                  ? _edit(context, controller, summary.customer)
                  : _delete(context, controller, summary.customer),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text(AppStrings.edit)),
                PopupMenuItem(value: 'delete', child: Text(AppStrings.delete)),
              ],
            ),
        ],
      ),
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => summary == null
            ? const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'الزبون غير موجود',
              )
            : _Statement(controller: controller, summary: summary),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    CustomerDetailsController controller,
    Customer customer,
  ) async {
    await showCustomerFormSheet(
      context,
      customer: customer,
      onSave: controller.update,
    );
  }

  Future<void> _delete(
    BuildContext context,
    CustomerDetailsController controller,
    Customer customer,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف الزبون',
      message: 'هل تريد حذف "${customer.name}"؟',
      confirmLabel: AppStrings.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final navigator = Navigator.of(context);
    final deleted = await runUiAction(context, controller.delete);
    if (deleted) navigator.pop();
  }
}

class _Statement extends StatelessWidget {
  const _Statement({required this.controller, required this.summary});

  final CustomerDetailsController controller;
  final CustomerSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final customer = summary.customer;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.phone.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(customer.phone, textDirection: TextDirection.ltr),
                    ],
                  ),
                if (customer.address.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(customer.address)),
                    ],
                  ),
                ],
                if (customer.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    customer.notes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (customer.phone.isNotEmpty ||
                    customer.address.isNotEmpty ||
                    customer.notes.isNotEmpty)
                  const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'المشتريات',
                        value: MoneyText(summary.totalPurchases),
                        caption: '${summary.invoiceCount} فاتورة',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        label: 'المدفوع',
                        color: scheme.success,
                        value: MoneyText(summary.totalPaid),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        label: 'الدين',
                        color: summary.hasDebt ? scheme.error : scheme.success,
                        value: MoneyText(summary.debt),
                      ),
                    ),
                  ],
                ),
                if (summary.hasDebt) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _pay(context),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('تسديد دفعة'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'الفواتير (${controller.invoices.length})',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (controller.invoices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('لا توجد فواتير لهذا الزبون')),
          )
        else
          for (final invoice in controller.invoices) ...[
            InvoiceCard(
              invoice: invoice,
              showProfit: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => InvoiceDetailsScreen(invoiceId: invoice.id),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        Text(
          'الدفعات المستلمة (${controller.receipts.length})',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (controller.receipts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('لم تُسجَّل دفعات تسديد بعد')),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < controller.receipts.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.savings_outlined,
                      color: scheme.success,
                    ),
                    title: Text(
                      AppDates.displayIso(controller.receipts[i].paidAt),
                    ),
                    subtitle: Text(
                      controller.receipts[i].note.isEmpty
                          ? AppDates.timeIso(controller.receipts[i].paidAt)
                          : '${AppDates.timeIso(controller.receipts[i].paidAt)}  •  ${controller.receipts[i].note}',
                    ),
                    trailing: MoneyText(
                      controller.receipts[i].amount,
                      color: scheme.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _pay(BuildContext context) async {
    final paid = await showReceivePaymentSheet(
      context,
      customerName: summary.customer.name,
      debt: summary.debt,
      onSubmit: (amount, note) => controller.receivePayment(amount, note: note),
    );
    if (paid == true && context.mounted) {
      showAppSnackBar(context, 'تم تسجيل الدفعة');
    }
  }
}
