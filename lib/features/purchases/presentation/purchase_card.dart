import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';
import 'package:flutter/material.dart';

/// One purchase in a list: number, customer, date and the money columns.
class PurchaseCard extends StatelessWidget {
  const PurchaseCard({
    super.key,
    required this.purchase,
    required this.onTap,
    this.showCustomer = true,
  });

  final Purchase purchase;
  final VoidCallback onTap;
  final bool showCustomer;

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
                      'شراء #${purchase.id}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${AppDates.displayIso(purchase.purchaseDate)}  '
                    '${AppDates.timeIso(purchase.createdAt)}',
                    style: muted,
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
              if (showCustomer) ...[
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
                        purchase.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 20),
              Row(
                children: [
                  _Figure(label: 'الإجمالي', amount: purchase.total),
                  _Figure(
                    label: 'المدفوع',
                    amount: purchase.paid,
                    color: scheme.success,
                  ),
                  if (purchase.isSettled)
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Chip(
                          label: const Text('خالص'),
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
                      label: 'المتبقي له',
                      amount: purchase.remaining,
                      color: scheme.primary,
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
