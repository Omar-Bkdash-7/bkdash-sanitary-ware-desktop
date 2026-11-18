import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';

/// One product line of an invoice, with the invoice it belongs to.
final class InvoiceLineExport {
  const InvoiceLineExport({
    required this.invoiceId,
    required this.invoiceDate,
    required this.customerName,
    required this.line,
  });

  final int invoiceId;
  final String invoiceDate;
  final String customerName;
  final InvoiceLineRecord line;
}
