import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';

/// An invoice line and how many of its pieces were already returned.
final class ReturnableLine {
  const ReturnableLine({
    required this.invoiceItemId,
    required this.line,
    required this.returned,
  });

  final int invoiceItemId;
  final InvoiceLineRecord line;

  /// Pieces of this line that already came back.
  final int returned;

  int get remaining => line.quantity - returned;

  bool get canReturn => remaining > 0;
}

/// One line of a return being written.
///
/// The prices are the ones the customer was actually charged: they are copied
/// from the invoice line, never from the current catalogue, so a return is
/// always credited at the price of that sale.
final class ReturnLine {
  const ReturnLine({
    required this.invoiceItemId,
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.sku,
    required this.container,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    required this.maxQuantity,
  });

  factory ReturnLine.fromReturnable(ReturnableLine entry, {int? quantity}) =>
      ReturnLine(
        invoiceItemId: entry.invoiceItemId,
        itemId: entry.line.itemId,
        itemName: entry.line.itemName,
        category: entry.line.category,
        sku: entry.line.sku,
        container: entry.line.container,
        unit: entry.line.unit,
        quantity: quantity ?? entry.remaining,
        unitCost: entry.line.unitCost,
        unitPrice: entry.line.unitPrice,
        maxQuantity: entry.remaining,
      );

  final int invoiceItemId;

  /// The inventory row the pieces go back to (`null` when it was deleted).
  final int? itemId;

  final String itemName;
  final String category;
  final String sku;
  final int container;
  final String unit;
  final int quantity;
  final Money unitCost;
  final Money unitPrice;

  /// The most that may be returned from this line.
  final int maxQuantity;

  Money get lineTotal => unitPrice * quantity;

  Money get lineCost => unitCost * quantity;

  ReturnLine copyWith({int? quantity}) => ReturnLine(
    invoiceItemId: invoiceItemId,
    itemId: itemId,
    itemName: itemName,
    category: category,
    sku: sku,
    container: container,
    unit: unit,
    quantity: quantity ?? this.quantity,
    unitCost: unitCost,
    unitPrice: unitPrice,
    maxQuantity: maxQuantity,
  );
}

/// A return being written: pure data and rules, no database.
final class ReturnDraft {
  const ReturnDraft({
    required this.invoiceId,
    this.lines = const <ReturnLine>[],
    this.refund = Money.zero,
    this.notes = '',
  });

  final int invoiceId;
  final List<ReturnLine> lines;

  /// Cash handed back to the customer now (never more than he had paid).
  final Money refund;
  final String notes;

  /// What the customer is credited, at the prices of the original sale.
  Money get total => Money.sum(lines.map((line) => line.lineTotal));

  /// What the returned pieces had cost the shop.
  Money get cost => Money.sum(lines.map((line) => line.lineCost));

  /// The part of the sale's profit that is given up with this return.
  Money get profit => total - cost;

  int get pieces => lines.fold(0, (sum, line) => sum + line.quantity);

  Iterable<ReturnLine> get selected => lines.where((line) => line.quantity > 0);

  ReturnDraft copyWith({
    List<ReturnLine>? lines,
    Money? refund,
    String? notes,
  }) => ReturnDraft(
    invoiceId: invoiceId,
    lines: lines ?? this.lines,
    refund: refund ?? this.refund,
    notes: notes ?? this.notes,
  );

  ReturnDraft updateQuantity(int index, int quantity) {
    final clamped = quantity.clamp(0, lines[index].maxQuantity);
    return copyWith(lines: [...lines]..[index] = lines[index].copyWith(
      quantity: clamped,
    ));
  }

  /// Throws a [ValidationException] when the return cannot be saved.
  void validate() {
    if (selected.isEmpty) {
      throw const ValidationException(
        'اختر كمية واحدة على الأقل لإرجاعها.',
      );
    }
    for (final line in selected) {
      if (line.quantity > line.maxQuantity) {
        throw ValidationException(
          'الكمية المرتجعة من "${line.itemName}" أكبر من المتبقي '
          '(${line.maxQuantity}).',
        );
      }
    }
    if (refund.isNegative || refund > total) {
      throw const ValidationException(
        'المبلغ المعاد للزبون يجب أن يكون بين صفر وإجمالي المرتجع.',
      );
    }
  }
}

/// One product line of a saved return (a copy of the invoice line).
final class ReturnLineRecord {
  const ReturnLineRecord({
    this.invoiceItemId,
    this.itemId,
    required this.itemName,
    required this.category,
    required this.sku,
    required this.container,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
  });

  factory ReturnLineRecord.fromRow(Map<String, Object?> row) =>
      ReturnLineRecord(
        invoiceItemId: row['invoice_item_id'] as int?,
        itemId: row['item_id'] as int?,
        itemName: row['item_name']! as String,
        category: row['category']! as String,
        sku: row['sku']! as String,
        container: (row['container'] as int?) ?? 0,
        unit: row['unit']! as String,
        quantity: row['quantity']! as int,
        unitCost: Money(row['unit_cost_cents']! as int),
        unitPrice: Money(row['unit_price_cents']! as int),
      );

  final int? invoiceItemId;
  final int? itemId;
  final String itemName;
  final String category;
  final String sku;
  final int container;
  final String unit;
  final int quantity;
  final Money unitCost;
  final Money unitPrice;

  Money get lineTotal => unitPrice * quantity;
}

/// A saved return of an invoice.
final class ReturnRecord {
  const ReturnRecord({
    required this.id,
    required this.invoiceId,
    required this.customerId,
    required this.customerName,
    required this.returnDate,
    required this.createdAt,
    required this.total,
    required this.cost,
    required this.refund,
    required this.notes,
    this.lines = const <ReturnLineRecord>[],
  });

  factory ReturnRecord.fromRow(
    Map<String, Object?> row, {
    List<ReturnLineRecord> lines = const <ReturnLineRecord>[],
  }) => ReturnRecord(
    id: row['id']! as int,
    invoiceId: row['invoice_id']! as int,
    customerId: row['customer_id'] as int?,
    customerName: (row['customer_name'] as String?) ?? '',
    returnDate: row['return_date']! as String,
    createdAt: row['created_at']! as String,
    total: Money(row['total_cents']! as int),
    cost: Money(row['cost_cents']! as int),
    refund: Money(row['refund_cents']! as int),
    notes: (row['notes'] as String?) ?? '',
    lines: lines,
  );

  final int id;
  final int invoiceId;
  final int? customerId;
  final String customerName;

  /// "2026-11-26"
  final String returnDate;

  /// "2026-11-26T10:15:00"
  final String createdAt;

  /// The credit given at the sale prices.
  final Money total;

  /// What the returned pieces had cost the shop.
  final Money cost;

  /// Cash handed back to the customer.
  final Money refund;
  final String notes;
  final List<ReturnLineRecord> lines;

  /// The debt this return cancels (credit minus the cash returned).
  Money get credit => total - refund;

  Money get profit => total - cost;
}
