import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';

/// The Arabic caption sent with the invoice PDF.
///
/// Plain text only (no `parse_mode`), so names that contain `*` or `_` are
/// delivered exactly as typed.
abstract final class InvoiceCaption {
  static String build(Invoice invoice) {
    final created = AppDates.tryParse(invoice.createdAt);
    return '🧾 فاتورة #${invoice.id}\n'
        '👤 الزبون: ${invoice.customerName}\n'
        '💰 الإجمالي: ${invoice.total.format()}\n'
        '✅ المدفوع: ${invoice.paid.format()}\n'
        '⏳ المتبقي: ${invoice.remaining.format()}\n'
        '📅 التاريخ: '
        '${created == null ? invoice.invoiceDate : '${AppDates.display(created)}  ${AppDates.time12(created)}'}';
  }
}
