import 'package:bkdash_sanitary_ware/core/formatting/money.dart';

/// A saved purchase from a customer (header only).
final class Purchase {
  const Purchase({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.purchaseDate,
    required this.createdAt,
    required this.total,
    required this.paid,
    required this.notes,
  });

  factory Purchase.fromRow(Map<String, Object?> row) => Purchase(
    id: row['id']! as int,
    customerId: row['customer_id']! as int,
    customerName: row['customer_name']! as String,
    customerPhone: (row['customer_phone'] as String?) ?? '',
    purchaseDate: row['purchase_date']! as String,
    createdAt: row['created_at']! as String,
    total: Money(row['total_cents']! as int),
    paid: Money(row['paid_cents']! as int),
    notes: (row['notes'] as String?) ?? '',
  );

  final int id;
  final int customerId;
  final String customerName;
  final String customerPhone;

  /// "2026-11-02"
  final String purchaseDate;

  /// "2026-11-02T15:30:05"
  final String createdAt;

  /// What the shop owes for the pieces.
  final Money total;

  /// Paid at the purchase or later.
  final Money paid;
  final String notes;

  Money get remaining => total - paid;

  bool get isSettled => !remaining.isPositive;
}

/// One product line of a saved purchase (a copy: later price changes or the
/// deletion of the product do not alter old purchases).
final class PurchaseLineRecord {
  const PurchaseLineRecord({
    required this.itemName,
    required this.category,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.unitCost,
  });

  factory PurchaseLineRecord.fromRow(Map<String, Object?> row) =>
      PurchaseLineRecord(
        itemName: row['item_name']! as String,
        category: row['category']! as String,
        sku: row['sku']! as String,
        unit: row['unit']! as String,
        quantity: row['quantity']! as int,
        unitCost: Money(row['unit_cost_cents']! as int),
      );

  final String itemName;
  final String category;
  final String sku;
  final String unit;
  final int quantity;
  final Money unitCost;

  Money get lineTotal => unitCost * quantity;
}

/// A payment made to the customer for a purchase.
final class PurchasePaymentRecord {
  const PurchasePaymentRecord({
    required this.amount,
    required this.paidAt,
    required this.isLaterPayment,
  });

  factory PurchasePaymentRecord.fromRow(Map<String, Object?> row) =>
      PurchasePaymentRecord(
        amount: Money(row['amount_cents']! as int),
        paidAt: row['paid_at']! as String,
        isLaterPayment: row['payout_id'] != null,
      );

  final Money amount;
  final String paidAt;

  /// `true` for a payout recorded later, `false` for the payment made when the
  /// purchase was saved.
  final bool isLaterPayment;
}

/// A purchase with its lines and payments.
final class PurchaseDetails {
  const PurchaseDetails({
    required this.purchase,
    required this.lines,
    required this.payments,
  });

  final Purchase purchase;
  final List<PurchaseLineRecord> lines;
  final List<PurchasePaymentRecord> payments;
}

/// Money paid to a customer against what the shop owes him.
final class CustomerPayout {
  const CustomerPayout({
    required this.id,
    required this.amount,
    required this.note,
    required this.paidAt,
  });

  factory CustomerPayout.fromRow(Map<String, Object?> row) => CustomerPayout(
    id: row['id']! as int,
    amount: Money(row['amount_cents']! as int),
    note: (row['note'] as String?) ?? '',
    paidAt: row['paid_at']! as String,
  );

  final int id;
  final Money amount;
  final String note;
  final String paidAt;
}
