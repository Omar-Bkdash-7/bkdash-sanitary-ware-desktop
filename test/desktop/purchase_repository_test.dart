import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/payment_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_draft.dart';
import 'package:bkdash_sanitary_ware/features/reports/data/report_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;

  late Directory root;
  late AppDatabase database;
  late DataChangeNotifier changes;
  late ItemRepository items;
  late CustomerRepository customers;
  late PurchaseRepository purchases;
  late PaymentRepository payments;
  late DateTime now;

  Clock clock() =>
      () => now;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('bkdash_purchase_repo_');
    database = await AppDatabase.open(
      factory: factory,
      directory: root.path,
      seed: false,
    );
    changes = DataChangeNotifier();
    now = DateTime(2026, 11, 20, 10);
    items = ItemRepository(database, changes, clock: clock());
    customers = CustomerRepository(database, changes, clock: clock());
    purchases = PurchaseRepository(database, changes, clock: clock());
    payments = PaymentRepository(database, changes, clock: clock());
  });

  tearDown(() async {
    changes.dispose();
    await database.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<Item> addItem({int quantity = 10}) => items.create(
    ItemInput(
      category: 'أنابيب',
      name: 'أنبوب',
      sku: 'PIP-1',
      unit: 'متر',
      cost: const Money(1000),
      price: const Money(1500),
      quantity: quantity,
      notes: '',
    ),
  );

  Future<Customer> addCustomer() =>
      customers.create(const CustomerInput(name: 'سامر', phone: '0999'));

  test(
    'a purchase grows the stock, averages the cost and records the debt',
    () async {
      final item = await addItem();
      final customer = await addCustomer();

      final purchaseId = await purchases.create(
        PurchaseDraft(
          customer: customer,
          lines: <PurchaseLine>[
            PurchaseLine.fromItem(
              item,
              quantity: 5,
              unitCost: const Money(2000),
            ),
          ],
          paidNow: const Money(3000),
        ),
      );

      final updated = await items.findById(item.id);
      expect(updated!.quantity, 15);
      // (10 * 1000 + 5 * 2000) / 15 = 1333.33...
      expect(updated.cost, const Money(1333));

      final summary = (await customers.getSummary(customer.id))!;
      expect(summary.purchaseCount, 1);
      expect(summary.totalPurchases, const Money(10000));
      expect(summary.totalPaidToCustomer, const Money(3000));
      expect(summary.purchasesOutstanding, const Money(7000));
      expect(summary.netBalance, const Money(-7000));
      expect(summary.amountPayable, const Money(7000));

      final details = (await purchases.getDetails(purchaseId))!;
      expect(details.lines, hasLength(1));
      expect(details.payments, hasLength(1));
      expect(details.payments.single.amount, const Money(3000));

      final report = await ReportRepository(
        database,
        InvoiceRepository(database, changes, clock: clock()),
        purchases,
      ).load(DateRange(now, now));
      expect(report.summary.purchaseCount, 1);
      expect(report.summary.purchases, const Money(10000));
      expect(report.summary.paidToCustomers, const Money(3000));
      expect(report.summary.payables, const Money(7000));
      expect(report.summary.netCash, const Money(-3000));
      expect(report.purchases.single.id, purchaseId);
      expect((await database.summarize()).purchases, 1);
    },
  );

  test('paying a customer settles the oldest purchase first', () async {
    final item = await addItem(quantity: 20);
    final customer = await addCustomer();

    final first = await purchases.create(
      PurchaseDraft(
        customer: customer,
        lines: <PurchaseLine>[
          PurchaseLine.fromItem(item, quantity: 5, unitCost: const Money(1000)),
        ],
        paidNow: const Money(1000),
      ),
    );
    now = DateTime(2026, 11, 21, 10);
    final second = await purchases.create(
      PurchaseDraft(
        customer: customer,
        lines: <PurchaseLine>[
          PurchaseLine.fromItem(item, quantity: 3, unitCost: const Money(1000)),
        ],
      ),
    );

    await purchases.payCustomer(
      customerId: customer.id,
      amount: const Money(4000),
    );
    var firstDetails = (await purchases.getDetails(first))!;
    var secondDetails = (await purchases.getDetails(second))!;
    expect(firstDetails.purchase.paid, const Money(5000));
    expect(secondDetails.purchase.paid, Money.zero);

    await purchases.payCustomer(
      customerId: customer.id,
      amount: const Money(3000),
    );
    firstDetails = (await purchases.getDetails(first))!;
    secondDetails = (await purchases.getDetails(second))!;
    expect(firstDetails.purchase.paid, const Money(5000));
    expect(secondDetails.purchase.paid, const Money(3000));

    final summary = (await customers.getSummary(customer.id))!;
    expect(summary.totalPurchases, const Money(8000));
    expect(summary.totalPaidToCustomer, const Money(8000));
    expect(summary.isSettled, isTrue);
    expect(await purchases.payoutsFor(customer.id), hasLength(2));

    await expectLater(
      purchases.payCustomer(customerId: customer.id, amount: const Money(1)),
      throwsA(isA<ValidationException>()),
    );
  });

  test(
    'deleting a purchase restores the stock only when nothing changed',
    () async {
      final item = await addItem();
      final customer = await addCustomer();

      final purchase = await purchases.create(
        PurchaseDraft(
          customer: customer,
          lines: <PurchaseLine>[
            PurchaseLine.fromItem(
              item,
              quantity: 5,
              unitCost: const Money(2000),
            ),
          ],
        ),
      );
      await purchases.delete(purchase);

      final restored = await items.findById(item.id);
      expect(restored!.quantity, 10);
      expect(restored.cost, const Money(1000));
      expect((await customers.getSummary(customer.id))!.isSettled, isTrue);

      final again = await purchases.create(
        PurchaseDraft(
          customer: customer,
          lines: <PurchaseLine>[
            PurchaseLine.fromItem(
              item,
              quantity: 5,
              unitCost: const Money(2000),
            ),
          ],
        ),
      );
      // A later sale means reversing the purchase would corrupt the stock.
      await database.db.rawUpdate(
        'UPDATE items SET quantity = quantity - 1 WHERE id = ?',
        <Object?>[item.id],
      );
      await expectLater(
        purchases.delete(again),
        throwsA(isA<ConflictException>()),
      );
      expect(await purchases.getPurchases(), hasLength(1));
    },
  );

  test('a purchase paid later can not be deleted', () async {
    final item = await addItem();
    final customer = await addCustomer();
    final purchase = await purchases.create(
      PurchaseDraft(
        customer: customer,
        lines: <PurchaseLine>[
          PurchaseLine.fromItem(item, quantity: 5, unitCost: const Money(1000)),
        ],
      ),
    );

    await purchases.payCustomer(
      customerId: customer.id,
      amount: const Money(1000),
    );
    await expectLater(
      purchases.delete(purchase),
      throwsA(isA<ConflictException>()),
    );
  });

  test('both sides of the account share one net balance', () async {
    final item = await addItem();
    final customer = await addCustomer();
    await database.db.insert('invoices', <String, Object?>{
      'customer_id': customer.id,
      'customer_name': customer.name,
      'customer_phone': customer.phone,
      'payment_method': 'cash',
      'invoice_date': '2026-11-19',
      'created_at': '2026-11-19T10:00:00',
      'total_cents': 10000,
      'paid_cents': 0,
      'profit_cents': 4000,
      'notes': '',
    });
    await purchases.create(
      PurchaseDraft(
        customer: customer,
        lines: <PurchaseLine>[
          PurchaseLine.fromItem(item, quantity: 3, unitCost: const Money(2000)),
        ],
        paidNow: const Money(1000),
      ),
    );

    var summary = (await customers.getSummary(customer.id))!;
    expect(summary.totalSales, const Money(10000));
    expect(summary.totalPurchases, const Money(6000));
    expect(summary.netBalance, const Money(5000));

    // The customer is still a net debtor: no payout to him.
    await expectLater(
      purchases.payCustomer(customerId: customer.id, amount: const Money(1)),
      throwsA(isA<ValidationException>()),
    );
    // A receipt can not exceed the net debt either.
    await expectLater(
      payments.receiveCustomerPayment(
        customerId: customer.id,
        amount: const Money(6000),
      ),
      throwsA(isA<ValidationException>()),
    );

    await payments.receiveCustomerPayment(
      customerId: customer.id,
      amount: const Money(5000),
    );
    summary = (await customers.getSummary(customer.id))!;
    expect(summary.totalReceived, const Money(5000));
    expect(summary.totalPaidToCustomer, const Money(1000));
    expect(summary.isSettled, isTrue);
  });
}
