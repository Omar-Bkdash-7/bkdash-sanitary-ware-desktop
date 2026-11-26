import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> row({
    int sales = 0,
    int salesPaid = 0,
    int purchases = 0,
    int purchasesPaid = 0,
  }) => <String, Object?>{
    'id': 1,
    'name': 'سامر',
    'phone': '0999',
    'address': '',
    'notes': '',
    'invoice_count': sales == 0 ? 0 : 1,
    'purchase_count': purchases == 0 ? 0 : 1,
    'sales_cents': sales,
    'sales_paid_cents': salesPaid,
    'purchases_cents': purchases,
    'purchases_paid_cents': purchasesPaid,
  };

  test('the customer owes when the unpaid sales are larger', () {
    final summary = CustomerSummary.fromRow(
      row(sales: 30000, salesPaid: 10000, purchases: 5000, purchasesPaid: 2000),
    );

    expect(summary.totalSales, const Money(30000));
    expect(summary.totalReceived, const Money(10000));
    expect(summary.totalPurchases, const Money(5000));
    expect(summary.totalPaidToCustomer, const Money(2000));
    expect(summary.netBalance, const Money(17000));
    expect(summary.amountDue, const Money(17000));
    expect(summary.amountPayable, Money.zero);
    expect(summary.customerOwes, isTrue);
    expect(summary.weOwe, isFalse);
    expect(summary.hasBalance, isTrue);
  });

  test('the shop owes when the unpaid purchases are larger', () {
    final summary = CustomerSummary.fromRow(
      row(sales: 5000, salesPaid: 5000, purchases: 8000, purchasesPaid: 1000),
    );

    expect(summary.netBalance, const Money(-7000));
    expect(summary.amountDue, Money.zero);
    expect(summary.amountPayable, const Money(7000));
    expect(summary.customerOwes, isFalse);
    expect(summary.weOwe, isTrue);
  });

  test('a customer with equal sides is settled', () {
    final summary = CustomerSummary.fromRow(
      row(sales: 4000, salesPaid: 1000, purchases: 5000, purchasesPaid: 2000),
    );

    expect(summary.netBalance, Money.zero);
    expect(summary.isSettled, isTrue);
    expect(summary.hasBalance, isFalse);
  });
}
