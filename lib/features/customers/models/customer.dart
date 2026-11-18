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

/// A customer together with what he bought and paid so far.
final class CustomerSummary {
  const CustomerSummary({
    required this.customer,
    required this.invoiceCount,
    required this.totalPurchases,
    required this.totalPaid,
  });

  factory CustomerSummary.fromRow(Map<String, Object?> row) => CustomerSummary(
    customer: Customer.fromRow(row),
    invoiceCount: row['invoice_count']! as int,
    totalPurchases: Money(row['total_cents']! as int),
    totalPaid: Money(row['paid_cents']! as int),
  );

  final Customer customer;
  final int invoiceCount;
  final Money totalPurchases;
  final Money totalPaid;

  /// What the customer still owes.
  Money get debt => totalPurchases - totalPaid;

  bool get hasDebt => debt.isPositive;
}
