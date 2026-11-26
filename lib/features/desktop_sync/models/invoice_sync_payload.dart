import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';

/// Turns a saved invoice into the two things the link sends: the Telegram
/// message and the JSON the desktop bridge stores.
///
/// Both are plain data (no database, no widgets), so they are covered by unit
/// tests and never depend on the screen that created the invoice.
abstract final class InvoiceSyncPayload {
  /// How many product lines fit comfortably in a Telegram message.
  static const int maxMessageLines = 20;

  /// The text sent to Telegram when an invoice is saved.
  static String telegramMessage({required InvoiceDetails details}) {
    final invoice = details.invoice;
    const divider = '━━━━━━━━━━━━━━';
    final created = AppDates.tryParse(invoice.createdAt);
    final buffer = StringBuffer()
      ..writeln('🧾 فاتورة جديدة #${invoice.id}')
      ..writeln('🏪 ${AppConstants.companyName}')
      ..writeln(divider)
      ..writeln(
        '📅 ${AppDates.displayIso(invoice.invoiceDate)}'
        '${created == null ? '' : ' — ${AppDates.time12(created)}'}',
      )
      ..writeln('👤 الزبون: ${invoice.customerName}');
    if (invoice.customerPhone.trim().isNotEmpty) {
      buffer.writeln('📞 ${invoice.customerPhone.trim()}');
    }
    buffer
      ..writeln('💳 الدفع: ${invoice.paymentMethod.label}')
      ..writeln(divider);

    final shown = details.lines.take(maxMessageLines).toList();
    for (var i = 0; i < shown.length; i++) {
      final line = shown[i];
      buffer.writeln(
        '${i + 1}) ${line.itemName} — ${line.quantity} × '
        '${line.unitPrice.format()} = ${line.lineTotal.format()}',
      );
    }
    final hidden = details.lines.length - shown.length;
    if (hidden > 0) buffer.writeln('… و $hidden سطراً آخر');

    buffer
      ..writeln(divider)
      ..writeln('📦 عدد القطع: ${pieces(details)}')
      ..writeln('💰 الإجمالي: ${invoice.total.format()}')
      ..writeln('✅ المدفوع: ${invoice.paid.format()}')
      ..writeln('⏳ المتبقي: ${invoice.remaining.format()}');
    if (invoice.notes.trim().isNotEmpty) {
      buffer.writeln('📝 ملاحظات: ${invoice.notes.trim()}');
    }
    return buffer.toString().trimRight();
  }

  /// Total number of pieces in the invoice.
  static int pieces(InvoiceDetails details) =>
      details.lines.fold(0, (sum, line) => sum + line.quantity);

  /// The invoice as the desktop bridge stores it.
  ///
  /// [deviceId] plus the local invoice number makes the `uid` the PC uses to
  /// know that a retried delivery is the same invoice.
  static Map<String, Object?> toJson({
    required InvoiceDetails details,
    required String deviceId,
    DateTime? sentAt,
  }) {
    final invoice = details.invoice;
    return <String, Object?>{
      'uid': '$deviceId:${invoice.id}',
      'device': deviceId,
      'sent_at': AppDates.isoDateTime(sentAt ?? DateTime.now()),
      'invoice': <String, Object?>{
        'number': invoice.id,
        'customer': invoice.customerName,
        'phone': invoice.customerPhone,
        'payment_method': invoice.paymentMethod.key,
        'date': invoice.invoiceDate,
        'created_at': invoice.createdAt,
        'total_cents': invoice.total.cents,
        'paid_cents': invoice.paid.cents,
        'profit_cents': invoice.profit.cents,
        'notes': invoice.notes,
      },
      'lines': <Map<String, Object?>>[
        for (final line in details.lines)
          <String, Object?>{
            'name': line.itemName,
            'category': line.category,
            'sku': line.sku,
            'container': line.container,
            'unit': line.unit,
            'quantity': line.quantity,
            'unit_cost_cents': line.unitCost.cents,
            'unit_price_cents': line.unitPrice.cents,
          },
      ],
    };
  }
}
