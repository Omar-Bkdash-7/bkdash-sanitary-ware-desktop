import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:flutter/material.dart';

/// One invoice in a list: number, customer, date and the money columns.
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({
    super.key,
    required this.invoice,
    required this.onTap,
    this.showProfit = true,
  });

  final Invoice invoice;
  final VoidCallback onTap;
  final bool showProfit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'فاتورة #${invoice.id}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(invoice.paymentMethod.label, style: muted),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      invoice.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${AppDates.displayIso(invoice.invoiceDate)}  ${AppDates.timeIso(invoice.createdAt)}',
                    style: muted,
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  _Figure(label: 'الإجمالي', amount: invoice.total),
                  _Figure(
                    label: 'المدفوع',
                    amount: invoice.paid,
                    color: scheme.success,
                  ),
                  if (invoice.remaining.isNegative)
                    _Figure(
                      label: 'رصيد للزبون',
                      amount: -invoice.remaining,
                      color: scheme.success,
                    )
                  else if (invoice.isSettled)
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Chip(
                          label: const Text('خالصة'),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide.none,
                          backgroundColor: scheme.success.withValues(
                            alpha: 0.12,
                          ),
                          labelStyle: TextStyle(color: scheme.success),
                        ),
                      ),
                    )
                  else
                    _Figure(
                      label: 'المتبقي',
                      amount: invoice.remaining,
                      color: scheme.error,
                    ),
                  if (showProfit)
                    _Figure(
                      label: 'الربح',
                      amount: invoice.profit,
                      color: scheme.info,
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

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.amount, this.color});

  final String label;
  final Money amount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: MoneyText(
              amount,
              color: color,
              fontWeight: FontWeight.bold,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
