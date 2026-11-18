import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

OutstandingInvoice _invoice(int id, int cents) =>
    OutstandingInvoice(invoiceId: id, remaining: Money(cents));

void main() {
  group('PaymentAllocator.allocate', () {
    test('settles the oldest invoice completely before the next one', () {
      final result = PaymentAllocator.allocate([
        _invoice(1, 10000),
        _invoice(2, 20000),
        _invoice(3, 5000),
      ], const Money(25000));

      expect(result.map((a) => a.invoiceId).toList(), [1, 2]);
      expect(result[0].amount, const Money(10000));
      expect(result[1].amount, const Money(15000));
    });

    test('a payment equal to the whole debt settles every invoice', () {
      final result = PaymentAllocator.allocate([
        _invoice(1, 100),
        _invoice(2, 250),
      ], const Money(350));

      expect(result, hasLength(2));
      expect(Money.sum(result.map((a) => a.amount)), const Money(350));
    });

    test('a small payment only touches the first invoice', () {
      final result = PaymentAllocator.allocate([
        _invoice(7, 1000),
        _invoice(8, 1000),
      ], const Money(300));

      expect(result, hasLength(1));
      expect(result.single.invoiceId, 7);
      expect(result.single.amount, const Money(300));
    });

    test('skips invoices that are already settled', () {
      final result = PaymentAllocator.allocate([
        _invoice(1, 0),
        _invoice(2, 500),
      ], const Money(200));

      expect(result.single.invoiceId, 2);
    });

    test('rejects a payment bigger than the debt', () {
      expect(
        () => PaymentAllocator.allocate([_invoice(1, 500)], const Money(501)),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects zero and negative payments', () {
      expect(
        () => PaymentAllocator.allocate([_invoice(1, 500)], Money.zero),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => PaymentAllocator.allocate([_invoice(1, 500)], const Money(-5)),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a payment when nothing is owed', () {
      expect(
        () => PaymentAllocator.allocate(
          const <OutstandingInvoice>[],
          const Money(1),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
