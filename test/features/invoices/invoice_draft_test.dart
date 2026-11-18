import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

const Item _valve = Item(
  id: 1,
  category: 'حنفيات',
  name: 'حنفية',
  sku: 'VAL-01',
  unit: 'قطعة',
  cost: Money(4500),
  price: Money(6500),
  quantity: 10,
  notes: '',
);

const Item _pipe = Item(
  id: 2,
  category: 'أنابيب',
  name: 'أنبوب',
  sku: 'PIP-01',
  unit: 'متر',
  cost: Money(300),
  price: Money(450),
  quantity: 100,
  notes: '',
);

const Customer _customer = Customer(
  id: 5,
  name: 'أحمد',
  phone: '0999',
  address: '',
  notes: '',
);

void main() {
  group('totals', () {
    test('total and profit are the sum of the lines', () {
      final draft = const InvoiceDraft()
          .addItem(_valve, quantity: 2)
          .addItem(_pipe, quantity: 10);

      expect(draft.total, const Money(2 * 6500 + 10 * 450));
      expect(draft.profit, const Money(2 * 2000 + 10 * 150));
      expect(draft.pieces, 12);
    });

    test('adding the same item twice merges the lines', () {
      final draft = const InvoiceDraft()
          .addItem(_valve)
          .addItem(_valve, quantity: 2);

      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.quantity, 3);
    });

    test('updateLine and removeLine change the right line', () {
      var draft = const InvoiceDraft().addItem(_valve).addItem(_pipe);
      draft = draft.updateLine(1, quantity: 4, unitPrice: const Money(500));

      expect(draft.lines[1].lineTotal, const Money(2000));
      expect(draft.lines[0].quantity, 1);
      expect(draft.removeLine(0).lines.single.itemId, 2);
    });
  });

  group('paid amount follows the payment method', () {
    final base = const InvoiceDraft().addItem(_valve, quantity: 2); // 13000

    test('cash and transfer are paid in full', () {
      expect(base.paid, const Money(13000));
      expect(
        base.copyWith(paymentMethod: PaymentMethod.transfer).paid,
        base.total,
      );
      expect(base.remaining, Money.zero);
    });

    test('credit leaves everything unpaid', () {
      final credit = base.copyWith(paymentMethod: PaymentMethod.credit);
      expect(credit.paid, Money.zero);
      expect(credit.remaining, const Money(13000));
    });

    test('partial uses the typed amount', () {
      final partial = base.copyWith(
        paymentMethod: PaymentMethod.partial,
        partialPaid: const Money(5000),
      );
      expect(partial.paid, const Money(5000));
      expect(partial.remaining, const Money(8000));
    });
  });

  group('validate', () {
    final withLine = const InvoiceDraft().addItem(_valve, quantity: 2);

    test('an empty invoice is rejected', () {
      expect(
        () => const InvoiceDraft().validate(),
        throwsA(isA<ValidationException>()),
      );
    });

    test('cash sale without a customer is fine', () {
      expect(withLine.validate, returnsNormally);
    });

    test('credit and partial sales need a customer', () {
      expect(
        () => withLine.copyWith(paymentMethod: PaymentMethod.credit).validate(),
        throwsA(isA<ValidationException>()),
      );
      expect(
        withLine
            .copyWith(paymentMethod: PaymentMethod.credit, customer: _customer)
            .validate,
        returnsNormally,
      );
    });

    test('a partial payment must be between zero and the total', () {
      final partial = withLine.copyWith(
        paymentMethod: PaymentMethod.partial,
        customer: _customer,
      );
      expect(partial.validate, throwsA(isA<ValidationException>()));
      expect(
        partial.copyWith(partialPaid: withLine.total).validate,
        throwsA(isA<ValidationException>()),
      );
      expect(
        partial.copyWith(partialPaid: const Money(1)).validate,
        returnsNormally,
      );
    });

    test('a line with quantity zero is rejected', () {
      expect(
        withLine.updateLine(0, quantity: 0).validate,
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
