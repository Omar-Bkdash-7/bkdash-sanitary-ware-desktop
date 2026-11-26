import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
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
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
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
  late PurchaseRepository purchases;
  late DateTime now;

  Clock clock() => () => now;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('bkdash_return_repo_');
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
    purchases = PurchaseRepository(database, changes, clock: clock());
  });

  tearDown(() async {
    changes.dispose();
    await database.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<Item> addItem({
    String sku = 'PIP-1',
    int container = 0,
    int quantity = 10,
    int cost = 1000,
    int price = 1500,
  }) => items.create(
    ItemInput(
      category: 'أنابيب',
      name: 'أنبوب',
      sku: sku,
      container: container,
      unit: 'متر',
      cost: Money(cost),
      price: Money(price),
      quantity: quantity,
      notes: '',
    ),
  );

  Future<Customer> addCustomer() =>
      customers.create(const CustomerInput(name: 'سامر', phone: '0999'));

  Future<int> sell({
    required Customer customer,
    required List<InvoiceLine> lines,
    PaymentMethod method = PaymentMethod.credit,
    Money paidNow = Money.zero,
  }) => invoices.create(
    InvoiceDraft(
      customer: customer,
      paymentMethod: method,
      lines: lines,
      partialPaid: paidNow,
    ),
  );

  test('a return gives the pieces back to their container at the sale price',
      () async {
    final first = await addItem(container: 1);
    final second = await addItem(
      container: 2,
      quantity: 5,
      cost: 1200,
      price: 2000,
    );
    final customer = await addCustomer();
    final invoiceId = await sell(
      customer: customer,
      lines: <InvoiceLine>[
        InvoiceLine.fromItem(first, quantity: 3).copyWith(
          unitPrice: const Money(1800),
        ),
        InvoiceLine.fromItem(second, quantity: 2).copyWith(
          unitPrice: const Money(2500),
        ),
      ],
    );

    final returnable = await returns.returnableLines(invoiceId);
    expect(returnable.map((line) => line.remaining), <int>[3, 2]);
    final line = returnable.firstWhere(
      (entry) => entry.line.container == 1,
    );
    await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[
          ReturnLine.fromReturnable(line, quantity: 2),
        ],
      ),
    );

    // Back to the row (and container) it came from, not the twin SKU.
    expect((await items.findById(first.id))!.quantity, 9);
    expect((await items.findById(second.id))!.quantity, 3);

    final saved = await returns.returnsForInvoice(invoiceId);
    expect(saved, hasLength(1));
    expect(saved.single.total, const Money(3600));
    expect(saved.single.refund, Money.zero);
    expect(saved.single.lines.single.unitPrice, const Money(1800));
    expect(saved.single.lines.single.container, 1);

    expect(
      (await returns.returnableLines(invoiceId)).first.remaining,
      1,
    );
    expect(
      (await CustomerBalanceQuery.net(database.db, customer.id)),
      // 3 x 1800 + 2 x 2500 = 10400 owed, minus the 3600 credit.
      const Money(6800),
    );

    final summary = (await customers.getSummary(customer.id))!;
    expect(summary.totalSales, const Money(10400));
    expect(summary.totalReturns, const Money(3600));
    expect(summary.netBalance, const Money(6800));

    final report = await ReportRepository(database, invoices, purchases).load(
      DateRange(now, now),
    );
    expect(report.summary.sales, const Money(10400));
    expect(report.summary.returns, const Money(3600));
    expect(report.summary.netSales, const Money(6800));
    // (3 x 800 + 2 x 1300) - (2 x 800) = 5000 - 1600.
    expect(report.summary.netProfit, const Money(3400));
    expect(report.summary.outstanding, const Money(6800));
    expect(report.summary.returnCount, 1);
    expect(report.summary.netCash, Money.zero);
    expect(report.categories.single.pieces, 3);
    expect(report.categories.single.sales, const Money(6800));
    expect(report.topItems.single.pieces, 3);
    expect(report.topItems.single.sales, const Money(6800));
  });

  test('cash handed back never exceeds what the customer paid', () async {
    final item = await addItem();
    final customer = await addCustomer();
    final invoiceId = await sell(
      customer: customer,
      lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 2)],
      method: PaymentMethod.partial,
      paidNow: const Money(1000),
    );
    final line = (await returns.returnableLines(invoiceId)).single;

    // More cash than the customer handed over is refused.
    await expectLater(
      returns.create(
        ReturnDraft(
          invoiceId: invoiceId,
          lines: <ReturnLine>[
            ReturnLine.fromReturnable(line, quantity: 1),
          ],
          refund: const Money(2000),
        ),
      ),
      throwsA(isA<ValidationException>()),
    );

    await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[
          ReturnLine.fromReturnable(line, quantity: 1),
        ],
        refund: const Money(1000),
      ),
    );
    // 3000 owed, 1000 paid, 1500 credited and 1000 handed back.
    expect(
      await CustomerBalanceQuery.net(database.db, customer.id),
      const Money(1500),
    );

    // All the cash went back with the first return: the second one is credit
    // only, even though it is worth 1500.
    final left = (await returns.returnableLines(invoiceId)).single;
    await expectLater(
      returns.create(
        ReturnDraft(
          invoiceId: invoiceId,
          lines: <ReturnLine>[ReturnLine.fromReturnable(left, quantity: 1)],
          refund: const Money(100),
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(left, quantity: 1)],
      ),
    );
    expect(await CustomerBalanceQuery.net(database.db, customer.id), Money.zero);
    expect((await items.findById(item.id))!.quantity, 10);
  });

  test('an invoice with a return can not be edited or deleted', () async {
    final item = await addItem();
    final customer = await addCustomer();
    final invoiceId = await sell(
      customer: customer,
      lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 2)],
    );
    final line = (await returns.returnableLines(invoiceId)).single;
    final returnId = await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 1)],
      ),
    );

    await expectLater(
      invoices.delete(invoiceId),
      throwsA(isA<ConflictException>()),
    );
    await expectLater(
      invoices.update(
        invoiceId,
        InvoiceDraft(
          customer: customer,
          paymentMethod: PaymentMethod.credit,
          lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 1)],
        ),
      ),
      throwsA(isA<ConflictException>()),
    );

    await returns.delete(returnId);
    expect((await items.findById(item.id))!.quantity, 8);
    expect(await returns.returnsForInvoice(invoiceId), isEmpty);
    expect((await CustomerBalanceQuery.net(database.db, customer.id)),
        const Money(3000));

    // With the return gone the invoice is editable again.
    await invoices.delete(invoiceId);
    expect((await items.findById(item.id))!.quantity, 10);
  });

  test('a return can not exceed what is left of the line', () async {
    final item = await addItem();
    final customer = await addCustomer();
    final invoiceId = await sell(
      customer: customer,
      lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 2)],
    );
    final line = (await returns.returnableLines(invoiceId)).single;
    expect(
      () => ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 3)],
      ).validate(),
      throwsA(isA<ValidationException>()),
    );

    final first = await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 2)],
      ),
    );
    final empty = (await returns.returnableLines(invoiceId)).single;
    expect(empty.canReturn, isFalse);
    await expectLater(
      returns.create(
        ReturnDraft(
          invoiceId: invoiceId,
          lines: <ReturnLine>[
            ReturnLine.fromReturnable(line, quantity: 1),
          ],
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    // The stock of a fully returned line is back to where it started.
    expect((await items.findById(item.id))!.quantity, 10);

    await returns.delete(first);
    expect((await items.findById(item.id))!.quantity, 8);
  });
}
