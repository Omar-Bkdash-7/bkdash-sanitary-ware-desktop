import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';

/// A saved invoice (header only).
final class Invoice {
  const Invoice({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMethod,
    required this.invoiceDate,
    required this.createdAt,
    required this.total,
    required this.paid,
    required this.profit,
    required this.notes,
  });

  factory Invoice.fromRow(Map<String, Object?> row) => Invoice(
    id: row['id']! as int,
    customerId: row['customer_id'] as int?,
    customerName: row['customer_name']! as String,
    customerPhone: (row['customer_phone'] as String?) ?? '',
    paymentMethod: PaymentMethod.fromKey(row['payment_method']! as String),
    invoiceDate: row['invoice_date']! as String,
    createdAt: row['created_at']! as String,
    total: Money(row['total_cents']! as int),
    paid: Money(row['paid_cents']! as int),
    profit: Money(row['profit_cents']! as int),
    notes: (row['notes'] as String?) ?? '',
  );

  final int id;
  final int? customerId;
  final String customerName;
  final String customerPhone;
  final PaymentMethod paymentMethod;

  /// "2026-11-02"
  final String invoiceDate;

  /// "2026-11-02T15:30:05"
  final String createdAt;
  final Money total;
  final Money paid;
  final Money profit;
  final String notes;

  Money get remaining => total - paid;

  bool get isSettled => !remaining.isPositive;
}

/// One product line of a saved invoice (a copy: later price changes or the
/// deletion of the product do not alter old invoices).
final class InvoiceLineRecord {
  const InvoiceLineRecord({
    this.itemId,
    required this.itemName,
    required this.category,
    required this.sku,
    this.container = 0,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
  });

  factory InvoiceLineRecord.fromRow(Map<String, Object?> row) =>
      InvoiceLineRecord(
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

  /// The inventory row the pieces came from (`null` when it was deleted).
  final int? itemId;

  final String itemName;
  final String category;
  final String sku;

  /// The container the pieces came from (`0` when not from one).
  final int container;

  final String unit;
  final int quantity;
  final Money unitCost;
  final Money unitPrice;

  Money get lineTotal => unitPrice * quantity;
  Money get lineProfit => (unitPrice - unitCost) * quantity;
}

/// A payment received for an invoice.
final class PaymentRecord {
  const PaymentRecord({
    required this.amount,
    required this.paidAt,
    required this.isDebtPayment,
  });

  factory PaymentRecord.fromRow(Map<String, Object?> row) => PaymentRecord(
    amount: Money(row['amount_cents']! as int),
    paidAt: row['paid_at']! as String,
    isDebtPayment: row['receipt_id'] != null,
  );

  final Money amount;
  final String paidAt;

  /// `true` for money collected later from the customer, `false` for the
  /// payment made when the invoice was issued.
  final bool isDebtPayment;
}

/// An invoice with its lines and payments.
final class InvoiceDetails {
  const InvoiceDetails({
    required this.invoice,
    required this.lines,
    required this.payments,
  });

  final Invoice invoice;
  final List<InvoiceLineRecord> lines;
  final List<PaymentRecord> payments;
}

/// Money collected from a customer against his debt.
final class CustomerReceipt {
  const CustomerReceipt({
    required this.id,
    required this.amount,
    required this.note,
    required this.paidAt,
  });

  factory CustomerReceipt.fromRow(Map<String, Object?> row) => CustomerReceipt(
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
