import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/invoice_sync_payload.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceDetails _details() => InvoiceDetails(
  invoice: const Invoice(
    id: 7,
    customerId: 3,
    customerName: 'أحمد الخطيب',
    customerPhone: '0955952550',
    paymentMethod: PaymentMethod.partial,
    invoiceDate: '2026-11-14',
    createdAt: '2026-11-14T15:30:05',
    total: Money(4500),
    paid: Money(2000),
    profit: Money(1000),
    notes: 'تسليم مساءً',
  ),
  lines: <InvoiceLineRecord>[
    const InvoiceLineRecord(
      itemName: 'ماسورة 1/2',
      category: 'مواسير',
      sku: 'P-1',
      unit: 'قطعة',
      quantity: 4,
      unitCost: Money(150),
      unitPrice: Money(250),
    ),
    const InvoiceLineRecord(
      itemName: 'خلاط مغسلة',
      category: 'خلاطات',
      sku: 'M-2',
      unit: 'قطعة',
      quantity: 5,
      unitCost: Money(2000),
      unitPrice: Money(700),
    ),
  ],
  payments: const <PaymentRecord>[],
);

void main() {
  group('telegramMessage', () {
    test('يعرض السطور والمجاميع والأرقام الصحيحة', () {
      final text = InvoiceSyncPayload.telegramMessage(details: _details());
      expect(text, contains('1) ماسورة 1/2 — 4 × \$2.50 = \$10.00'));
      expect(text, contains('2) خلاط مغسلة — 5 × \$7.00 = \$35.00'));
      expect(text, contains('عدد القطع: 9'));
      expect(text, contains('الإجمالي: \$45.00'));
      expect(text, contains('المدفوع: \$20.00'));
      expect(text, contains('المتبقي: \$25.00'));
      expect(text, contains('دفعة جزئية'));
      expect(text, contains('📝 ملاحظات: تسليم مساءً'));
      expect(text, contains('2026/11/14'));
    });
  });

  group('toJson', () {
    test('يحمل معرّفاً فريداً لكل جهاز ولكل فاتورة', () {
      final payload = InvoiceSyncPayload.toJson(
        details: _details(),
        deviceId: 'abc123',
      );
      expect(payload['uid'], 'abc123:7');
      expect(payload['device'], 'abc123');
    });

    test('يحوّل المبالغ إلى سنتات والأسطر كما هي', () {
      final payload = InvoiceSyncPayload.toJson(
        details: _details(),
        deviceId: 'abc123',
      );
      final invoice = payload['invoice']! as Map<String, Object?>;
      expect(invoice['total_cents'], 4500);
      expect(invoice['paid_cents'], 2000);
      expect(invoice['payment_method'], 'partial');
      expect(invoice['date'], '2026-11-14');

      final lines = payload['lines']! as List<Map<String, Object?>>;
      expect(lines, hasLength(2));
      expect(lines.first['quantity'], 4);
      expect(lines.first['unit_price_cents'], 250);
      expect(lines.first['sku'], 'P-1');
    });
  });
}
