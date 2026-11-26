import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_draft.dart';
import 'package:flutter_test/flutter_test.dart';

const Customer _customer = Customer(
  id: 1,
  name: 'سامر',
  phone: '0999',
  address: '',
  notes: '',
);

const Item _valve = Item(
  id: 10,
  category: 'حنفيات',
  name: 'حنفية',
  sku: 'VAL-01',
  unit: 'قطعة',
  cost: Money(4000),
  price: Money(6500),
  quantity: 2,
  notes: '',
);

PurchaseDraft _draftWith(List<PurchaseLine> lines, {Money? paidNow}) =>
    PurchaseDraft(
      customer: _customer,
      lines: lines,
      paidNow: paidNow ?? Money.zero,
    );

PurchaseLine _newLine({
  String name = 'خلاط',
  String sku = 'MIX-01',
  int quantity = 2,
  Money cost = const Money(3000),
  Money price = const Money(5000),
}) => PurchaseLine.newItem(
  itemName: name,
  category: 'خلاطات',
  sku: sku,
  unit: 'قطعة',
  quantity: quantity,
  unitCost: cost,
  salePrice: price,
);

void main() {
  group('PurchaseDraft totals', () {
    test('adding the same item merges its quantity into one line', () {
      final draft = const PurchaseDraft(
        customer: _customer,
      ).addItem(_valve, quantity: 2).addItem(_valve, quantity: 3);

      expect(draft.lines, hasLength(1));
      expect(draft.lines.single.quantity, 5);
      expect(draft.total, const Money(20000));
      expect(draft.pieces, 5);
    });

    test('new items keep their purchase and sale prices', () {
      final draft = const PurchaseDraft(
        customer: _customer,
      ).addNewItem(_newLine(quantity: 3));

      expect(draft.lines.single.isNewItem, isTrue);
      expect(draft.lines.single.lineTotal, const Money(9000));
      expect(draft.lines.single.salePrice, const Money(5000));
    });

    test('remaining is the total minus what was paid now', () {
      final draft = _draftWith([
        _newLine(quantity: 2),
      ], paidNow: const Money(1000));

      expect(draft.total, const Money(6000));
      expect(draft.remaining, const Money(5000));
    });
  });

  group('PurchaseDraft.validate', () {
    test('accepts a complete purchase', () {
      final draft = _draftWith([_newLine()], paidNow: const Money(6000));
      expect(draft.validate, returnsNormally);
    });

    test('rejects an empty purchase', () {
      expect(
        const PurchaseDraft(customer: _customer).validate,
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a paid amount larger than the total', () {
      final draft = _draftWith([
        _newLine(quantity: 1),
      ], paidNow: const Money(3001));
      expect(draft.validate, throwsA(isA<ValidationException>()));
    });

    test('rejects a quantity below one', () {
      final draft = _draftWith([_newLine(quantity: 0)]);
      expect(draft.validate, throwsA(isA<ValidationException>()));
    });

    test('rejects the same item written twice', () {
      final draft = _draftWith([
        PurchaseLine.fromItem(_valve),
        PurchaseLine.fromItem(_valve),
      ]);
      expect(draft.validate, throwsA(isA<ValidationException>()));
    });

    test('rejects a duplicate code for two new items', () {
      final draft = _draftWith([
        _newLine(name: 'خلاط أول', sku: 'MIX-01'),
        _newLine(name: 'خلاط ثان', sku: 'mix-01'),
      ]);
      expect(draft.validate, throwsA(isA<ValidationException>()));
    });
  });
}
