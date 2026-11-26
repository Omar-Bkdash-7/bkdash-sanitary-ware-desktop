import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
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
import 'package:bkdash_sanitary_ware/features/purchases/presentation/create_purchase_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The customers, what each one owes and what the shop owes him.
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
        heroTag: 'customers-add',
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
          child: _BalanceBanner(controller: controller),
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
                label: const Text('أرصدة مفتوحة'),
                selected: controller.onlyOpen,
                onSelected: (value) => controller.setOnlyOpen(value: value),
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
                      : controller.onlyOpen
                      ? 'كل الحسابات خالصة'
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
                    onPurchase: () => _purchase(context, customers[index]),
                    onPay: () => _pay(context, customers[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _purchase(BuildContext context, CustomerSummary summary) async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => CreatePurchaseScreen(customer: summary.customer),
      ),
    );
    if (id != null && context.mounted) {
      showAppSnackBar(context, 'تم حفظ عملية الشراء #$id');
    }
  }

  Future<void> _pay(BuildContext context, CustomerSummary summary) async {
    final paidOut = summary.weOwe
        ? await showPayCustomerSheet(
            context,
            customerName: summary.customer.name,
            payable: summary.amountPayable,
            onSubmit: (amount, note) => controller.payCustomer(
              customerId: summary.customer.id,
              amount: amount,
              note: note,
            ),
          )
        : await showReceivePaymentSheet(
            context,
            customerName: summary.customer.name,
            debt: summary.amountDue,
            onSubmit: (amount, note) => controller.receivePayment(
              customerId: summary.customer.id,
              amount: amount,
              note: note,
            ),
          );
    if (paidOut == true && context.mounted) {
      showAppSnackBar(
        context,
        summary.weOwe ? 'تم تسجيل الدفع للزبون' : 'تم تسجيل الدفعة',
      );
    }
  }
}

class _BalanceBanner extends StatelessWidget {
  const _BalanceBanner({required this.controller});

  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = controller.netBalance;
    final color = net.isPositive
        ? scheme.error
        : net.isNegative
        ? scheme.primary
        : scheme.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                net.isZero
                    ? Icons.verified_outlined
                    : Icons.account_balance_wallet_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('أرصدة الزبائن'),
                    Text(
                      net.isZero
                          ? 'كل الحسابات خالصة'
                          : '${controller.debtorCount} مدين  •  '
                                '${controller.creditorCount} دائن',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SideAmount(
                  label: 'لنا عند الزبائن',
                  amount: controller.totalReceivable,
                  color: scheme.error,
                ),
              ),
              Container(width: 1, height: 32, color: scheme.outlineVariant),
              const SizedBox(width: 12),
              Expanded(
                child: _SideAmount(
                  label: 'علينا للزبائن',
                  amount: controller.totalPayable,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SideAmount extends StatelessWidget {
  const _SideAmount({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final Money amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        MoneyText(
          amount,
          color: amount.isPositive ? color : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.summary,
    required this.onOpen,
    required this.onPurchase,
    required this.onPay,
  });

  final CustomerSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onPurchase;
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
          child: Column(
            children: [
              Row(
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
                          '${summary.invoiceCount} فاتورة  •  '
                          '${summary.purchaseCount} شراء',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _NetBalance(summary: summary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onPurchase,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('شراء'),
                  ),
                  const Spacer(),
                  if (summary.hasBalance)
                    OutlinedButton.icon(
                      onPressed: onPay,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: Icon(
                        summary.weOwe
                            ? Icons.call_made_rounded
                            : Icons.call_received_rounded,
                        size: 16,
                      ),
                      label: Text(summary.weOwe ? 'الدفع' : 'تسديد'),
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

class _NetBalance extends StatelessWidget {
  const _NetBalance({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (summary.isSettled) {
      return Text(
        'خالص',
        style: TextStyle(color: scheme.success, fontWeight: FontWeight.bold),
      );
    }
    final owes = summary.customerOwes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          owes ? 'عليه' : 'له عندنا',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        MoneyText(
          owes ? summary.amountDue : summary.amountPayable,
          color: owes ? scheme.error : scheme.primary,
          fontWeight: FontWeight.bold,
          style: theme.textTheme.titleSmall,
        ),
      ],
    );
  }
}
