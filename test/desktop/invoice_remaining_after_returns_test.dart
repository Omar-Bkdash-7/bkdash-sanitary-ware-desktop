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
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_card.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/data/report_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:bkdash_sanitary_ware/features/returns/data/return_repository.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';
import 'package:flutter/material.dart';
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
    root = Directory.systemTemp.createTempSync('bkdash_remaining_');
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

  /// A 4500 invoice, 1500 paid when it was issued and one of its three pieces
  /// returned for 1500 of credit: 1500 is left to collect, not 3000.
  Future<Invoice> sellAndReturnOne() async {
    final item = await items.create(
      ItemInput(
        category: 'أنابيب',
        name: 'أنبوب',
        sku: 'PIP-1',
        container: 0,
        unit: 'متر',
        cost: const Money(1000),
        price: const Money(1500),
        quantity: 10,
        notes: '',
      ),
    );
    final customer = await customers.create(
      const CustomerInput(name: 'سامر', phone: '0999'),
    );
    final invoiceId = await invoices.create(
      InvoiceDraft(
        customer: customer,
        paymentMethod: PaymentMethod.partial,
        partialPaid: const Money(1500),
        lines: <InvoiceLine>[InvoiceLine.fromItem(item, quantity: 3)],
      ),
    );
    final line = (await returns.returnableLines(invoiceId)).single;
    await returns.create(
      ReturnDraft(
        invoiceId: invoiceId,
        lines: <ReturnLine>[ReturnLine.fromReturnable(line, quantity: 1)],
      ),
    );
    return (await invoices.getDetails(invoiceId))!.invoice;
  }

  test('the invoice list and details keep the credit of the return', () async {
    await sellAndReturnOne();

    final listed = (await invoices.getInvoices()).single;
    expect(listed.total, const Money(4500));
    expect(listed.paid, const Money(1500));
    expect(listed.returnedCredit, const Money(1500));
    expect(listed.remaining, const Money(1500));
    expect(listed.isSettled, isFalse);

    final details = (await invoices.getDetails(listed.id))!;
    expect(details.invoice.remaining, const Money(1500));
  });

  test('the report summary and its invoice list are net of the returns',
      () async {
    await sellAndReturnOne();

    final report = await ReportRepository(database, invoices, purchases).load(
      DateRange(now, now),
    );
    expect(report.summary.sales, const Money(4500));
    expect(report.summary.returns, const Money(1500));
    expect(report.summary.outstanding, const Money(1500));
    expect(report.invoices.single.remaining, const Money(1500));
  });

  test('a later collection can not take the returned credit twice', () async {
    final invoice = await sellAndReturnOne();
    final customerId = invoice.customerId!;

    await expectLater(
      payments.receiveCustomerPayment(
        customerId: customerId,
        amount: const Money(2000),
      ),
      throwsA(isA<ValidationException>()),
    );
    await payments.receiveCustomerPayment(
      customerId: customerId,
      amount: const Money(1500),
    );
    final settled = (await invoices.getInvoices()).single;
    expect(settled.remaining, Money.zero);
    expect(settled.isSettled, isTrue);
  });

  testWidgets('the invoice card shows the remaining after the returns',
      (tester) async {
    final invoice = Invoice(
      id: 7,
      customerId: 1,
      customerName: 'سامر',
      customerPhone: '',
      paymentMethod: PaymentMethod.partial,
      invoiceDate: '2026-11-26',
      createdAt: '2026-11-26T10:00:00',
      total: const Money(4500),
      paid: const Money(1000),
      profit: const Money(1500),
      notes: '',
      returnedCredit: const Money(1500),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InvoiceCard(invoice: invoice, onTap: () {})),
      ),
    );

    // 4500 - 1000 - 1500 = 2000, not the 3500 the invoice alone would show.
    expect(find.text('المتبقي'), findsOneWidget);
    expect(find.text(const Money(2000).format()), findsOneWidget);
    expect(find.text(const Money(3500).format()), findsNothing);
    expect(find.text('خالصة'), findsNothing);
  });
}
