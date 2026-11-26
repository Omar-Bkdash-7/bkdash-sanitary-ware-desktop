import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';

/// A registered customer.
final class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.notes,
  });

  factory Customer.fromRow(Map<String, Object?> row) => Customer(
    id: row['id']! as int,
    name: row['name']! as String,
    phone: (row['phone'] as String?) ?? '',
    address: (row['address'] as String?) ?? '',
    notes: (row['notes'] as String?) ?? '',
  );

  final int id;
  final String name;
  final String phone;
  final String address;
  final String notes;
}

/// What the user types in the add / edit customer form.
final class CustomerInput {
  const CustomerInput({
    required this.name,
    this.phone = '',
    this.address = '',
    this.notes = '',
  });

  factory CustomerInput.fromCustomer(Customer customer) => CustomerInput(
    name: customer.name,
    phone: customer.phone,
    address: customer.address,
    notes: customer.notes,
  );

  final String name;
  final String phone;
  final String address;
  final String notes;

  void validate() {
    if (name.trim().isEmpty) {
      throw const ValidationException(AppStrings.requiredField);
    }
  }
}

/// A customer together with everything sold to him and bought from him.
///
/// The shop and the customer can be creditors at the same time: he may still
/// owe for old invoices while the shop owes him for pieces it bought. The
/// number that matters for settlement is [netBalance].
final class CustomerSummary {
  const CustomerSummary({
    required this.customer,
    required this.invoiceCount,
    required this.purchaseCount,
    required this.totalSales,
    required this.totalReceived,
    required this.totalPurchases,
    required this.totalPaidToCustomer,
  });

  factory CustomerSummary.fromRow(Map<String, Object?> row) => CustomerSummary(
    customer: Customer.fromRow(row),
    invoiceCount: (row['invoice_count'] as num?)?.toInt() ?? 0,
    purchaseCount: (row['purchase_count'] as num?)?.toInt() ?? 0,
    totalSales: Money((row['sales_cents'] as num?)?.toInt() ?? 0),
    totalReceived: Money((row['sales_paid_cents'] as num?)?.toInt() ?? 0),
    totalPurchases: Money((row['purchases_cents'] as num?)?.toInt() ?? 0),
    totalPaidToCustomer: Money(
      (row['purchases_paid_cents'] as num?)?.toInt() ?? 0,
    ),
  );

  final Customer customer;

  /// Invoices issued to the customer.
  final int invoiceCount;

  /// Purchases made from the customer.
  final int purchaseCount;

  /// Total of the invoices (what the customer bought from the shop).
  final Money totalSales;

  /// Money received from the customer for those invoices.
  final Money totalReceived;

  /// Total of the purchases (what the shop bought from the customer).
  final Money totalPurchases;

  /// Money paid to the customer for those purchases.
  final Money totalPaidToCustomer;

  /// Unpaid part of the invoices.
  Money get salesOutstanding => totalSales - totalReceived;

  /// Unpaid part of the purchases.
  Money get purchasesOutstanding => totalPurchases - totalPaidToCustomer;

  /// Positive: the customer owes the shop. Negative: the shop owes him.
  Money get netBalance => salesOutstanding - purchasesOutstanding;

  bool get customerOwes => netBalance.isPositive;

  bool get weOwe => netBalance.isNegative;

  bool get hasBalance => !netBalance.isZero;

  /// What the customer owes, or zero when the shop owes him.
  Money get amountDue => customerOwes ? netBalance : Money.zero;

  /// What the shop owes, or zero when the customer owes it.
  Money get amountPayable => weOwe ? -netBalance : Money.zero;

  bool get isSettled => netBalance.isZero;
}
