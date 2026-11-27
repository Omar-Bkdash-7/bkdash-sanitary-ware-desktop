import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_balance_query.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/payment_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_draft.dart';
import 'package:bkdash_sanitary_ware/features/reports/data/report_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:bkdash_sanitary_ware/features/returns/data/return_repository.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';
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
  late InvoiceRepository invoices;
  late ReturnRepository returns;
  late PaymentRepository payments;
  late PurchaseRepository purchases;
  late DateTime now;

  Clock clock() => () => now;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('bkdash_integrity_');
    database = await AppDatabase.open(
      factory: factory,
      directory: root.path,
      seed: false,
    );
    changes = DataChangeNotifier();
    now = DateTime(2026, 11, 26, 10);
    items = ItemRepository(database, changes, clock: clock());
    customers = CustomerRepository(database, changes, clock: clock());
    invoices = InvoiceRepository(database, changes, clock: clock());
    returns = ReturnRepository(database, changes, clock: clock());
    payments = PaymentRepository(database, changes, clock: clock());
    purchases = PurchaseRepository(database, changes, clock: clock());
  });

  tearDown(() async {
    changes.dispose();
    await database.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<Item> addItem({
    int quantity = 10,
    int cost = 1000,
    int price = 1500,
  }) => items.create(
    ItemInput(
      category: 'أنابيب',
      name: 'أنبوب',
      sku: 'PIP-1',
      container: 0,
      unit: 'متر',
      cost: Money(cost),
      price: Money(price),
      quantity: quantity,
      notes: '',
    ),
  );

  Future<Customer> addCustomer([String name = 'سامر']) =>
      customers.create(CustomerInput(name: name, phone: '0999'));

  /// Every money row must agree with the header it belongs to.
  Future<void> expectMoneyRowsAddUp() async {
    final db = database.db;
    final invoiceGap = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ('
      ' SELECT i.id FROM invoices i LEFT JOIN payments p ON p.invoice_id = i.id'
      ' GROUP BY i.id'
      ' HAVING i.paid_cents <> IFNULL(SUM(p.amount_cents), 0))',
    )).first.readInt('n');
    expect(invoiceGap, 0, reason: 'invoice paid_cents != its payments');
    final purchaseGap = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ('
      ' SELECT b.id FROM purchases b'
      ' LEFT JOIN purchase_payments pp ON pp.purchase_id = b.id'
      ' GROUP BY b.id'
      ' HAVING b.paid_cents <> IFNULL(SUM(pp.amount_cents), 0))',
    )).first.readInt('n');
    expect(purchaseGap, 0, reason: 'purchase paid_cents != its payments');
    final returnGap = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ('
      ' SELECT r.id FROM returns r'
      ' LEFT JOIN return_items ri ON ri.return_id = r.id'
      ' GROUP BY r.id'
      ' HAVING r.total_cents <> IFNULL(SUM(ri.quantity * ri.unit_price_cents), 0))',
    )).first.readInt('n');
    expect(returnGap, 0, reason: 'return total != its lines');
  }

  test('the stock is conserved by every operation', () async {
    final item = await addItem();
    final customer = await addCustomer();

    // A sale takes the pieces out of the row it was sold from.
    final invoiceId = await invoices.create(
      InvoiceDraft(
        customer: customer,
        paymentMethod: PaymentMethod.credit,
        lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 3)],
      ),
    );
    expect((await items.findById(item.id))!.quantity, 7);

    // A return puts them back.
    final line = (await returns.returnableLines(invoiceId)).single;
    final returnId = await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 2)],
      ),
    );
    expect((await items.findById(item.id))!.quantity, 9);

    // Deleting the return takes them out again.
    await returns.delete(returnId);
    expect((await items.findById(item.id))!.quantity, 7);

    // A purchase adds the pieces and re-averages the cost.
    final purchaseId = await purchases.create(
      PurchaseDraft(
        customer: customer,
        lines: <PurchaseLine>[
          PurchaseLine.fromItem(
            (await items.findById(item.id))!,
            quantity: 5,
            unitCost: const Money(1200),
          ),
        ],
      ),
    );
    var saved = (await items.findById(item.id))!;
    expect(saved.quantity, 12);
    // (7 x 1000 + 5 x 1200) / 12 rounded.
    expect(saved.cost, const Money(1083));

    // Deleting the purchase reverses both.
    await purchases.delete(purchaseId);
    saved = (await items.findById(item.id))!;
    expect(saved.quantity, 7);
    expect(saved.cost, const Money(1000));

    // Deleting the invoice gives back what it took.
    await invoices.delete(invoiceId);
    expect((await items.findById(item.id))!.quantity, 10);
  });

  test('the customer balance always equals his documents', () async {
    final item = await addItem();
    final customer = await addCustomer();

    Future<void> expectBalanceMatchesDocuments() async {
      final db = database.db;
      final rows = await db.rawQuery(
        'SELECT '
        '(SELECT IFNULL(SUM(total_cents - paid_cents), 0) FROM invoices '
        ' WHERE customer_id = ?1) - '
        '(SELECT IFNULL(SUM(total_cents - paid_cents), 0) FROM purchases '
        ' WHERE customer_id = ?1) - '
        '(SELECT IFNULL(SUM(total_cents - refund_cents), 0) FROM returns '
        ' WHERE customer_id = ?1) AS expected',
        <Object?>[customer.id],
      );
      final expected = Money(rows.first.readInt('expected'));
      expect(await CustomerBalanceQuery.net(db, customer.id), expected);
      expect((await customers.getSummary(customer.id))!.netBalance, expected);
    }

    // 4500 sold, 1500 paid at the counter, one piece returned (1500).
    final invoiceId = await invoices.create(
      InvoiceDraft(
        customer: customer,
        paymentMethod: PaymentMethod.partial,
        partialPaid: const Money(1500),
        lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 3)],
      ),
    );
    await expectBalanceMatchesDocuments();
    expect(
      await CustomerBalanceQuery.net(database.db, customer.id),
      const Money(3000),
    );

    final line = (await returns.returnableLines(invoiceId)).single;
    await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 1)],
      ),
    );
    await expectBalanceMatchesDocuments();

    // The rest of the debt, collected later.
    await payments.receiveCustomerPayment(
      customerId: customer.id,
      amount: const Money(1500),
    );
    await expectBalanceMatchesDocuments();
    expect(await CustomerBalanceQuery.net(database.db, customer.id), Money.zero);

    // The shop buys from him: it owes him now.
    await purchases.create(
      PurchaseDraft(
        customer: customer,
        lines: <PurchaseLine>[
          PurchaseLine.fromItem(
            (await items.findById(item.id))!,
            quantity: 4,
            unitCost: const Money(800),
          ),
        ],
      ),
    );
    await expectBalanceMatchesDocuments();
    expect(
      await CustomerBalanceQuery.net(database.db, customer.id),
      const Money(-3200),
    );

    await purchases.payCustomer(
      customerId: customer.id,
      amount: const Money(3200),
    );
    await expectBalanceMatchesDocuments();
    expect(await CustomerBalanceQuery.net(database.db, customer.id), Money.zero);
    await expectMoneyRowsAddUp();
  });

  test('a return credit left on a paid invoice can still be paid out',
      () async {
    final item = await addItem();
    final customer = await addCustomer();
    // A cash sale: nothing is owed.
    final invoiceId = await invoices.create(
      InvoiceDraft(
        customer: customer,
        paymentMethod: PaymentMethod.cash,
        lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 2)],
      ),
    );
    // 3000 paid, one piece back for 1500 of credit and no cash at the counter.
    final line = (await returns.returnableLines(invoiceId)).single;
    final returnId = await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 1)],
      ),
    );
    expect(
      await CustomerBalanceQuery.net(database.db, customer.id),
      const Money(-1500),
    );

    // Paying him now must clear that credit, not leave it hanging.
    await purchases.payCustomer(
      customerId: customer.id,
      amount: const Money(1500),
    );
    expect(await CustomerBalanceQuery.net(database.db, customer.id), Money.zero);
    final saved = (await returns.returnsForInvoice(invoiceId)).single;
    expect(saved.id, returnId);
    expect(saved.refund, const Money(1500));
    expect(saved.credit, Money.zero);

    // The cash went out once: in the payout the reports count.
    final report = await ReportRepository(database, invoices, purchases).load(
      DateRange(now, now),
    );
    expect(report.summary.paidToCustomers, const Money(1500));
    expect(report.summary.outstanding, Money.zero);
  });

  test('missing or negative amounts are refused, not written', () async {
    final item = await addItem();
    final customer = await addCustomer();
    await invoices.create(
      InvoiceDraft(
        customer: customer,
        paymentMethod: PaymentMethod.credit,
        lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 1)],
      ),
    );

    await expectLater(
      payments.receiveCustomerPayment(
        customerId: customer.id,
        amount: Money.zero,
      ),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      payments.receiveCustomerPayment(
        customerId: customer.id,
        amount: const Money(-500),
      ),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      purchases.payCustomer(
        customerId: customer.id,
        amount: Money.zero,
      ),
      throwsA(isA<ValidationException>()),
    );
    await expectMoneyRowsAddUp();
  });

  test('the reports agree with the tables they summarize', () async {
    final item = await addItem();
    final customer = await addCustomer();
    final invoiceId = await invoices.create(
      InvoiceDraft(
        customer: customer,
        paymentMethod: PaymentMethod.partial,
        partialPaid: const Money(500),
        lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 2)],
      ),
    );
    final line = (await returns.returnableLines(invoiceId)).single;
    await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 1)],
        refund: const Money(200),
      ),
    );
    await purchases.create(
      PurchaseDraft(
        customer: customer,
        lines: <PurchaseLine>[
          PurchaseLine.fromItem(
            (await items.findById(item.id))!,
            quantity: 2,
            unitCost: const Money(700),
          ),
        ],
        paidNow: const Money(400),
      ),
    );

    final report = await ReportRepository(database, invoices, purchases).load(
      DateRange(now, now),
    );
    final db = database.db;
    Future<int> one(String sql) async =>
        (await db.rawQuery(sql)).first.readInt('n');

    expect(report.summary.sales, const Money(3000));
    expect(
      report.summary.sales,
      Money(await one('SELECT SUM(total_cents) AS n FROM invoices')),
    );
    expect(
      report.summary.returns,
      Money(await one('SELECT SUM(total_cents) AS n FROM returns')),
    );
    // 3000 - 500 - (1500 - 200) = 1200 left on the invoice.
    expect(report.summary.outstanding, const Money(1200));
    expect(
      report.summary.collected,
      Money(await one('SELECT SUM(amount_cents) AS n FROM payments')),
    );
    expect(
      report.summary.purchases,
      Money(await one('SELECT SUM(total_cents) AS n FROM purchases')),
    );
    // Payouts plus the payment made when the purchase itself was saved.
    expect(
      report.summary.paidToCustomers,
      Money(
        await one('SELECT SUM(amount_cents) AS n FROM customer_payouts') +
            await one(
              'SELECT SUM(amount_cents) AS n FROM purchase_payments '
              'WHERE payout_id IS NULL',
            ),
      ),
    );
    expect(report.summary.payables, const Money(1000));
    // 500 received - 400 paid - 200 handed back.
    expect(report.summary.netCash, const Money(-100));
    expect(
      report.summary.netSales,
      report.summary.sales - report.summary.returns,
    );
    expect(report.summary.netProfit.isPositive, isTrue);
    await expectMoneyRowsAddUp();
  });
}
