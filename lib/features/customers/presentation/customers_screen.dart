import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customer_details_screen.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customer_form_sheet.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customers_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/receive_payment_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The customers and what each one owes.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CustomersController>();
    return Scaffold(
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => _CustomersBody(controller: controller),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCustomerFormSheet(
          context,
          onSave: (input) async {
            await controller.addCustomer(input);
          },
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('زبون جديد'),
      ),
    );
  }
}

class _CustomersBody extends StatelessWidget {
  const _CustomersBody({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final customers = controller.visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _DebtBanner(controller: controller),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  hint: 'ابحث بالاسم أو الهاتف...',
                  onChanged: controller.setQuery,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('عليهم ذمة'),
                selected: controller.onlyDebtors,
                onSelected: (value) => controller.setOnlyDebtors(value: value),
              ),
            ],
          ),
        ),
        Expanded(
          child: customers.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: controller.all.isEmpty
                      ? 'لا يوجد زبائن بعد'
                      : 'لا توجد نتائج مطابقة',
                  message: controller.all.isEmpty
                      ? 'أضف زبوناً، أو سيُضاف تلقائياً عند أول فاتورة آجلة.'
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _CustomerCard(
                    summary: customers[index],
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomerDetailsScreen(
                          customerId: customers[index].customer.id,
                        ),
                      ),
                    ),
                    onPay: () => _pay(context, customers[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _pay(BuildContext context, CustomerSummary summary) async {
    final paid = await showReceivePaymentSheet(
      context,
      customerName: summary.customer.name,
      debt: summary.debt,
      onSubmit: (amount, note) => controller.receivePayment(
        customerId: summary.customer.id,
        amount: amount,
        note: note,
      ),
    );
    if (paid == true && context.mounted) {
      showAppSnackBar(context, 'تم تسجيل الدفعة');
    }
  }
}

class _DebtBanner extends StatelessWidget {
  const _DebtBanner({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasDebt = controller.totalDebt.isPositive;
    final color = hasDebt ? scheme.error : scheme.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            hasDebt
                ? Icons.account_balance_wallet_outlined
                : Icons.verified_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي الذمم على الزبائن'),
                Text(
                  hasDebt
                      ? '${controller.debtorCount} زبون عليهم ذمة'
                      : 'لا توجد ذمم مستحقة',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          MoneyText(
            controller.totalDebt,
            color: color,
            fontWeight: FontWeight.bold,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.summary,
    required this.onOpen,
    required this.onPay,
  });

  final CustomerSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final customer = summary.customer;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(customer.name.characters.first),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (customer.phone.isNotEmpty)
                      Text(
                        customer.phone,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.invoiceCount} فاتورة  •  مشتريات '
                      '${summary.totalPurchases.format()}',
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (summary.hasDebt) ...[
                    MoneyText(
                      summary.debt,
                      color: scheme.error,
                      fontWeight: FontWeight.bold,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton(
                      onPressed: onPay,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('تسديد'),
                    ),
                  ] else
                    Text(
                      'خالص',
                      style: TextStyle(
                        color: scheme.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
