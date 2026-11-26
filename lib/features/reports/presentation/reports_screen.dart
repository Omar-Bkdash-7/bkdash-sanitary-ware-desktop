import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/core/widgets/stat_tile.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_card.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_details_screen.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/purchase_card.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/purchase_details_screen.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:bkdash_sanitary_ware/features/reports/presentation/reports_charts.dart';
import 'package:bkdash_sanitary_ware/features/reports/presentation/reports_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Sales, profit, collections and debts for a chosen period.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    return Column(
      children: [
        _PeriodBar(controller: controller),
        Expanded(
          child: LoadStateView(
            status: controller.status,
            errorMessage: controller.errorMessage,
            onRetry: controller.load,
            builder: (context) {
              final data = controller.data;
              return data == null
                  ? const SizedBox.shrink()
                  : _ReportBody(data: data);
            },
          ),
        ),
      ],
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.controller});

  final ReportsController controller;

  Future<void> _pickRange(BuildContext context) async {
    final range = controller.range;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
      locale: const Locale('ar'),
      helpText: 'اختر الفترة',
      saveText: 'تطبيق',
    );
    if (picked != null) {
      await controller.setCustomRange(DateRange(picked.start, picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = controller.range;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final period in ReportPeriod.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      avatar: period == ReportPeriod.custom
                          ? const Icon(Icons.date_range_rounded, size: 18)
                          : null,
                      label: Text(period.label),
                      selected: controller.period == period,
                      onSelected: (_) => period == ReportPeriod.custom
                          ? _pickRange(context)
                          : controller.selectPeriod(period),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'من ${AppDates.display(range.from)} إلى ${AppDates.display(range.to)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.data});

  final ReportData data;

  /// A long period can hold thousands of records: only the newest are listed.
  static const int _maxListedRecords = 50;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = data.summary;
    final listed = data.invoices.take(_maxListedRecords).toList();
    final listedPurchases = data.purchases.take(_maxListedRecords).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'إجمالي المبيعات',
                icon: Icons.point_of_sale_rounded,
                value: MoneyText(summary.sales),
                caption: '${summary.invoiceCount} فاتورة',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'صافي الأرباح',
                icon: Icons.trending_up_rounded,
                color: scheme.success,
                value: MoneyText(summary.profit),
                caption: 'هامش ${summary.margin.toStringAsFixed(1)}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'المقبوضات',
                icon: Icons.payments_outlined,
                color: scheme.info,
                value: MoneyText(summary.collected),
                caption: 'نقد محصَّل خلال الفترة',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'الذمم المتبقية',
                icon: Icons.account_balance_wallet_outlined,
                color: summary.outstanding.isPositive
                    ? scheme.error
                    : scheme.success,
                value: MoneyText(summary.outstanding),
                caption: 'على فواتير الفترة',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'الشراء من الزبائن',
                icon: Icons.shopping_cart_outlined,
                value: MoneyText(summary.purchases),
                caption: '${summary.purchaseCount} عملية',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'مستحق للزبائن',
                icon: Icons.call_made_rounded,
                color: summary.payables.isPositive
                    ? scheme.primary
                    : scheme.success,
                value: MoneyText(summary.payables),
                caption: 'على عمليات شراء الفترة',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'المدفوع للزبائن',
                icon: Icons.payments_outlined,
                color: scheme.info,
                value: MoneyText(summary.paidToCustomers),
                caption: 'نقد دُفع خلال الفترة',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'صافي النقد',
                icon: Icons.account_balance_outlined,
                color: summary.netCash.isNegative
                    ? scheme.error
                    : scheme.success,
                value: MoneyText(summary.netCash),
                caption: 'المقبوض ناقص المدفوع للزبائن',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (summary.invoiceCount == 0 && summary.purchaseCount == 0)
          const _NothingSold()
        else ...[
          if (summary.invoiceCount > 0) ...[
            _SectionCard(
              title: data.groupedByMonth
                  ? 'المبيعات والأرباح شهرياً'
                  : 'المبيعات والأرباح يومياً',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(color: scheme.primary, label: 'مبيعات'),
                  const SizedBox(width: 12),
                  _LegendDot(color: scheme.success, label: 'أرباح'),
                ],
              ),
              child: SalesBarChart(
                series: data.series,
                byMonth: data.groupedByMonth,
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'المبيعات حسب الفئة',
              child: CategoryPieChart(categories: data.categories),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'الأصناف الأكثر مبيعاً',
              child: Column(
                children: [
                  for (var i = 0; i < data.topItems.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(data.topItems[i].name),
                      subtitle: Text('${data.topItems[i].pieces} قطعة'),
                      trailing: MoneyText(
                        data.topItems[i].sales,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'فواتير الفترة (${data.invoices.length})',
              style: theme.textTheme.titleMedium,
            ),
            if (data.invoices.length > _maxListedRecords)
              Text(
                'تُعرض أحدث $_maxListedRecords فاتورة فقط.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            for (final invoice in listed) ...[
              InvoiceCard(
                invoice: invoice,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InvoiceDetailsScreen(invoiceId: invoice.id),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (summary.purchaseCount > 0) ...[
            const SizedBox(height: 16),
            Text(
              'الشراء من الزبائن (${summary.purchaseCount})',
              style: theme.textTheme.titleMedium,
            ),
            if (data.purchases.length > _maxListedRecords)
              Text(
                'تُعرض أحدث $_maxListedRecords عملية فقط.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            for (final purchase in listedPurchases) ...[
              PurchaseCard(
                purchase: purchase,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PurchaseDetailsScreen(purchaseId: purchase.id),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ],
    );
  }
}

class _NothingSold extends StatelessWidget {
  const _NothingSold();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.insights_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'لا توجد مبيعات أو عمليات شراء في هذه الفترة',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
