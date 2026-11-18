import 'dart:io';
import 'dart:typed_data';

import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_pdf_service.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Reads an asset straight from the project folder (no asset bundle needed).
Future<ByteData> _asset(String key) async {
  final bytes = await File(key).readAsBytes();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

InvoiceLineRecord _line(String name, {int quantity = 1, int price = 12000}) =>
    InvoiceLineRecord(
      itemName: name,
      category: 'أدوات صحية',
      sku: 'ITM-0001',
      unit: 'قطعة',
      quantity: quantity,
      unitCost: Money(price - 3000),
      unitPrice: Money(price),
    );

void main() {
  late Directory folder;

  setUp(() async {
    folder = Directory(p.join(Directory.systemTemp.path, 'bkdash_pdf_test'));
    if (folder.existsSync()) await folder.delete(recursive: true);
  });

  InvoicePdfService service() => InvoicePdfService(
    loadAsset: _asset,
    outputDirectory: () async => folder,
    clock: () => DateTime(2026, 11, 16, 15, 30),
  );

  Invoice invoice({int id = 7}) => Invoice(
    id: id,
    customerId: 1,
    customerName: 'عمر بكداش',
    customerPhone: '0955952550',
    paymentMethod: PaymentMethod.partial,
    invoiceDate: '2026-11-16',
    createdAt: '2026-11-16T15:30:05',
    total: Money(32500),
    paid: Money(20000),
    profit: Money(7500),
    notes: 'تسليم فوري — مغسلة الحمام',
  );

  test('renders an Arabic invoice and names the file in ASCII', () async {
    final file = await service().create(
      details: InvoiceDetails(
        invoice: invoice(),
        lines: <InvoiceLineRecord>[
          _line('خلاط مغسلة ستانلس', quantity: 2),
          _line('سيفون كامل', price: 8500),
        ],
        payments: const <PaymentRecord>[],
      ),
      previousDebt: Money(4500),
    );

    final bytes = await file.readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
    expect(p.basename(file.path), 'invoice_7_2026-11-16.pdf');
    // ignore: avoid_print
    print('SAMPLE: ${file.path}');
  });

  test('a long invoice spills over several pages', () async {
    final lines = List<InvoiceLineRecord>.generate(
      45,
      (index) => _line('صنف رقم ${index + 1}'),
    );
    final file = await service().create(
      details: InvoiceDetails(
        invoice: invoice(id: 9),
        lines: lines,
        payments: const <PaymentRecord>[],
      ),
    );

    final bytes = await file.readAsBytes();
    // Every page dictionary carries its own MediaBox.
    final pages = '/MediaBox'.allMatches(String.fromCharCodes(bytes)).length;
    expect(pages, greaterThanOrEqualTo(2));
    // ignore: avoid_print
    print('SAMPLE_LONG: ${file.path}');
  });
}
