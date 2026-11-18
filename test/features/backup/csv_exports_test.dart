import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/csv_exports.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_line_export.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _lines(String csv) => csv
    .replaceFirst('\uFEFF', '')
    .split('\r\n')
    .where((l) => l.isNotEmpty)
    .toList();

void main() {
  test('inventory export has a header and one row per item', () {
    final csv = CsvExports.inventory(const [
      Item(
        id: 1,
        category: 'حنفيات',
        name: 'حنفية "ممتازة", نحاس',
        sku: 'VAL-01',
        unit: 'قطعة',
        cost: Money(4500),
        price: Money(6500),
        quantity: 10,
        notes: '',
      ),
    ]);
    final lines = _lines(csv);

    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(lines, hasLength(2));
    expect(lines[0].split(',').first, 'الصنف');
    expect(
      lines[1],
      'حنفيات,"حنفية ""ممتازة"", نحاس",VAL-01,قطعة,45.00,65.00,10,450.00,650.00,',
    );
  });

  test('invoice export writes totals, paid, remaining and profit', () {
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
    final lines = _lines(CsvExports.invoices(const [invoice]));

    expect(lines, hasLength(2));
    expect(
      lines[1],
      '7,2026/11/02,03:30 م,أحمد,0999,دفعة جزئية,130.00,50.00,80.00,40.00,',
    );
  });

  test('invoice lines export has one row per sold line', () {
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
    final lines = _lines(CsvExports.invoiceLines(const [export]));

    expect(
      lines[1],
      '7,2026/11/02,أحمد,أنابيب,أنبوب,PIP-01,متر,10,4.50,45.00,15.00',
    );
  });

  test('customers export lists the debt of each customer', () {
    const summary = CustomerSummary(
      customer: Customer(
        id: 1,
        name: 'سامر',
        phone: '',
        address: 'دمشق',
        notes: '',
      ),
      invoiceCount: 2,
      totalPurchases: Money(30000),
      totalPaid: Money(12000),
    );
    final lines = _lines(CsvExports.customers(const [summary]));

    expect(lines[1], 'سامر,,دمشق,2,300.00,120.00,180.00');
  });
}
