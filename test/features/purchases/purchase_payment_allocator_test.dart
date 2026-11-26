import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_payment_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const purchases = <OutstandingPurchase>[
    OutstandingPurchase(purchaseId: 1, remaining: Money(1000)),
    OutstandingPurchase(purchaseId: 2, remaining: Money(2000)),
    OutstandingPurchase(purchaseId: 3, remaining: Money(3000)),
  ];

  test('pays the oldest purchase completely before the next one', () {
    final allocations = PurchasePaymentAllocator.allocate(
      purchases,
      const Money(3500),
    );

    expect(allocations, hasLength(3));
    expect(allocations[0].purchaseId, 1);
    expect(allocations[0].amount, const Money(1000));
    expect(allocations[1].purchaseId, 2);
    expect(allocations[1].amount, const Money(2000));
    expect(allocations[2].purchaseId, 3);
    expect(allocations[2].amount, const Money(500));
  });

  test('skips purchases that are already settled', () {
    final allocations = PurchasePaymentAllocator.allocate(const [
      OutstandingPurchase(purchaseId: 1, remaining: Money.zero),
      OutstandingPurchase(purchaseId: 2, remaining: Money(500)),
    ], const Money(500));

    expect(allocations, hasLength(1));
    expect(allocations.single.purchaseId, 2);
  });

  test('rejects a payment above the total payable', () {
    expect(
      () => PurchasePaymentAllocator.allocate(purchases, const Money(6001)),
      throwsA(isA<ValidationException>()),
    );
  });

  test('rejects a zero or negative payment', () {
    expect(
      () => PurchasePaymentAllocator.allocate(purchases, Money.zero),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => PurchasePaymentAllocator.allocate(purchases, const Money(-100)),
      throwsA(isA<ValidationException>()),
    );
  });

  test('rejects any payment when nothing is owed', () {
    expect(
      () => PurchasePaymentAllocator.allocate(
        const <OutstandingPurchase>[],
        const Money(100),
      ),
      throwsA(isA<ValidationException>()),
    );
  });
}
