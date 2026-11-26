import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/xlsx_exports.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_line_export.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_line_export.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveFile _part(List<int> workbook, String name) {
  final archive = ZipDecoder().decodeBytes(workbook);
  final file = archive.findFile(name);
  expect(file, isNotNull, reason: 'missing $name');
  return file!;
}

String _text(ArchiveFile part) => utf8.decode(part.content);

void main() {
  test('inventory workbook has a header, numbers and Arabic text', () {
    final bytes = XlsxExports.inventory(const [
      Item(
        id: 1,
        category: 'حنفيات',
        name: 'حنفية "ممتازة", نحاس & <سعر>',
        sku: 'VAL-01',
        unit: 'قطعة',
        cost: Money(4500),
        price: Money(6500),
        quantity: 10,
        notes: '=1+1',
      ),
    ]);

    expect(bytes.take(2), <int>[0x50, 0x4B]);
    final sheet = _text(_part(bytes, 'xl/worksheets/sheet1.xml'));
    final workbook = _text(_part(bytes, 'xl/workbook.xml'));

    expect(workbook, contains('name="المخزون"'));
    expect(sheet, contains('rightToLeft="1"'));
    expect(sheet, contains('الصنف'));
    expect(sheet, contains('حنفية &quot;ممتازة&quot;, نحاس &amp; &lt;سعر&gt;'));
    expect(sheet, contains('<v>45.0</v>'));
    expect(sheet, contains('<v>65.0</v>'));
    expect(sheet, contains('<v>10</v>'));
    // A note that looks like a formula stays text: Excel must not run it.
    expect(sheet, contains('=1+1'));
    expect(sheet, isNot(contains('<f>')));
  });

  test('invoice workbook writes totals as numbers and phone as text', () {
    const invoice = Invoice(
      id: 7,
      customerId: 3,
      customerName: 'أحمد',
      customerPhone: '0999',
      paymentMethod: PaymentMethod.partial,
      invoiceDate: '2026-11-02',
      createdAt: '2026-11-02T15:30:05',
      total: Money(13000),
      paid: Money(5000),
      profit: Money(4000),
      notes: '',
    );

    final sheet = _text(
      _part(XlsxExports.invoices(const [invoice]), 'xl/worksheets/sheet1.xml'),
    );

    expect(sheet, contains('رقم الفاتورة'));
    expect(sheet, contains('2026/11/02'));
    expect(sheet, contains('أحمد'));
    expect(sheet, contains('>0999<'));
    expect(sheet, contains('<v>130.0</v>'));
    expect(sheet, contains('<v>50.0</v>'));
    expect(sheet, contains('<v>80.0</v>'));
    expect(sheet, contains('<v>40.0</v>'));
  });

  test('invoice lines workbook lists each sold line', () {
    const export = InvoiceLineExport(
      invoiceId: 7,
      invoiceDate: '2026-11-02',
      customerName: 'أحمد',
      line: InvoiceLineRecord(
        itemName: 'أنبوب',
        category: 'أنابيب',
        sku: 'PIP-01',
        unit: 'متر',
        quantity: 10,
        unitCost: Money(300),
        unitPrice: Money(450),
      ),
    );

    final sheet = _text(
      _part(
        XlsxExports.invoiceLines(const [export]),
        'xl/worksheets/sheet1.xml',
      ),
    );

    expect(sheet, contains('أنبوب'));
    expect(sheet, contains('PIP-01'));
    expect(sheet, contains('<v>10</v>'));
    expect(sheet, contains('<v>4.5</v>'));
    expect(sheet, contains('<v>45.0</v>'));
    expect(sheet, contains('<v>15.0</v>'));
  });

  test('purchase workbook lists each purchase with its remaining amount', () {
    const purchase = Purchase(
      id: 4,
      customerId: 1,
      customerName: 'سامر',
      customerPhone: '0999',
      purchaseDate: '2026-11-02',
      createdAt: '2026-11-02T15:30:05',
      total: Money(9000),
      paid: Money(3000),
      notes: '',
    );

    final sheet = _text(
      _part(
        XlsxExports.purchases(const [purchase]),
        'xl/worksheets/sheet1.xml',
      ),
    );

    expect(sheet, contains('رقم الشراء'));
    expect(sheet, contains('2026/11/02'));
    expect(sheet, contains('سامر'));
    expect(sheet, contains('>0999<'));
    expect(sheet, contains('<v>90.0</v>'));
    expect(sheet, contains('<v>30.0</v>'));
    expect(sheet, contains('<v>60.0</v>'));
  });

  test('purchase lines workbook lists each bought line', () {
    const export = PurchaseLineExport(
      purchaseId: 4,
      purchaseDate: '2026-11-02',
      customerName: 'سامر',
      line: PurchaseLineRecord(
        itemName: 'خلاط',
        category: 'خلاطات',
        sku: 'MIX-01',
        unit: 'قطعة',
        quantity: 2,
        unitCost: Money(3000),
      ),
    );

    final sheet = _text(
      _part(
        XlsxExports.purchaseLines(const [export]),
        'xl/worksheets/sheet1.xml',
      ),
    );

    expect(sheet, contains('خلاط'));
    expect(sheet, contains('MIX-01'));
    expect(sheet, contains('<v>2</v>'));
    expect(sheet, contains('<v>30.0</v>'));
    expect(sheet, contains('<v>60.0</v>'));
  });

  test('customers workbook lists both sides of the balance', () {
    const summary = CustomerSummary(
      customer: Customer(
        id: 1,
        name: 'سامر',
        phone: '',
        address: 'دمشق',
        notes: '',
      ),
      invoiceCount: 2,
      purchaseCount: 1,
      totalSales: Money(30000),
      totalReceived: Money(12000),
      totalPurchases: Money(5000),
      totalPaidToCustomer: Money(2000),
    );

    final sheet = _text(
      _part(
        XlsxExports.customers(const [summary]),
        'xl/worksheets/sheet1.xml',
      ),
    );

    expect(sheet, contains('سامر'));
    expect(sheet, contains('دمشق'));
    expect(sheet, contains('إجمالي المبيعات'));
    expect(sheet, contains('<v>2</v>'));
    expect(sheet, contains('<v>300.0</v>'));
    expect(sheet, contains('<v>120.0</v>'));
    expect(sheet, contains('<v>50.0</v>'));
    expect(sheet, contains('<v>20.0</v>'));
    expect(sheet, contains('<v>150.0</v>'));
  });
}
