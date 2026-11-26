import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';

/// One product line of a purchase, with its header, for the CSV export.
final class PurchaseLineExport {
  const PurchaseLineExport({
    required this.purchaseId,
    required this.purchaseDate,
    required this.customerName,
    required this.line,
  });

  final int purchaseId;
  final String purchaseDate;
  final String customerName;
  final PurchaseLineRecord line;
}
