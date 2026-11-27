import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';
import 'package:flutter/material.dart';

/// One saved return in a list, with the day a later payout settled its credit.
///
/// A return whose credit was paid down by a payout can not be deleted: the
/// payout would be left without the record it settled. The tile says so before
/// the user tries, and the delete button stays disabled for it.
class ReturnTile extends StatelessWidget {
  const ReturnTile({super.key, required this.entry, required this.onDelete});

  final ReturnRecord entry;
  final VoidCallback onDelete;

  /// "سُوّي رصيده لاحقاً عبر سند صرف بتاريخ 26/11/2026" when it was settled.
  static String settlementNote(ReturnRecord entry) =>
      'سُوّي رصيده لاحقاً عبر سند صرف بتاريخ '
      '${AppDates.displayIso(entry.settledAt)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pieces = entry.lines.fold<int>(0, (sum, line) => sum + line.quantity);
    final settled = entry.settledAt.isNotEmpty;
    return ListTile(
      leading: Icon(Icons.assignment_return_outlined, color: scheme.error),
      title: Text('مرتجع #${entry.id}  •  ${entry.total.format()}'),
      subtitle: Text(
        '${AppDates.displayIso(entry.returnDate)}  •  $pieces قطعة'
        '${entry.refund.isPositive ? '  •  أُعيد نقداً ${entry.refund.format()}' : ''}'
        '${settled ? '\n${settlementNote(entry)}' : ''}'
        '${entry.notes.isNotEmpty ? '\n${entry.notes}' : ''}',
        style: settled
            ? theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)
            : null,
      ),
      isThreeLine: entry.notes.isNotEmpty || settled,
      trailing: IconButton(
        tooltip: settled
            ? '${settlementNote(entry)} — لا يمكن حذفه'
            : 'حذف المرتجع',
        icon: const Icon(Icons.undo_rounded),
        onPressed: settled ? null : onDelete,
      ),
    );
  }
}
