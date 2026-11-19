import 'dart:typed_data';

import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/xlsx_writer.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_line_export.dart';

/// Builds the `.xlsx` workbook of each export (no files, no database: easy to
/// test).
abstract final class XlsxExports {
  static Uint8List inventory(List<Item> items) {
    final xlsx = XlsxWriter(sheetName: 'المخزون')
      ..writeRow(const <Object?>[
        'الصنف',
        'اسم المادة',
        'الرمز',
        'الوحدة',
        'سعر التكلفة',
        'سعر البيع',
        'الكمية',
        'قيمة المخزون (تكلفة)',
        'قيمة المخزون (بيع)',
        'ملاحظات',
      ]);
    for (final item in items) {
      xlsx.writeRow(<Object?>[
        item.category,
        item.name,
        item.sku,
        item.unit,
        _amount(item.cost),
        _amount(item.price),
        item.quantity,
        _amount(item.stockCostValue),
        _amount(item.stockSaleValue),
        item.notes,
      ]);
    }
    return xlsx.build();
  }

  static Uint8List invoices(List<Invoice> invoices) {
    final xlsx = XlsxWriter(sheetName: 'الفواتير')
      ..writeRow(const <Object?>[
        'رقم الفاتورة',
        'التاريخ',
        'الوقت',
        'الزبون',
        'الهاتف',
        'طريقة الدفع',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'الربح',
        'ملاحظات',
      ]);
    for (final invoice in invoices) {
      xlsx.writeRow(<Object?>[
        invoice.id,
        AppDates.displayIso(invoice.invoiceDate),
        AppDates.timeIso(invoice.createdAt),
        invoice.customerName,
        invoice.customerPhone,
        invoice.paymentMethod.label,
        _amount(invoice.total),
        _amount(invoice.paid),
        _amount(invoice.remaining),
        _amount(invoice.profit),
        invoice.notes,
      ]);
    }
    return xlsx.build();
  }

  static Uint8List invoiceLines(List<InvoiceLineExport> lines) {
    final xlsx = XlsxWriter(sheetName: 'الأصناف المباعة')
      ..writeRow(const <Object?>[
        'رقم الفاتورة',
        'التاريخ',
        'الزبون',
        'الصنف',
        'اسم المادة',
        'الرمز',
        'الوحدة',
        'الكمية',
        'سعر البيع',
        'إجمالي السطر',
        'ربح السطر',
      ]);
    for (final entry in lines) {
      final line = entry.line;
      xlsx.writeRow(<Object?>[
        entry.invoiceId,
        AppDates.displayIso(entry.invoiceDate),
        entry.customerName,
        line.category,
        line.itemName,
        line.sku,
        line.unit,
        line.quantity,
        _amount(line.unitPrice),
        _amount(line.lineTotal),
        _amount(line.lineProfit),
      ]);
    }
    return xlsx.build();
  }

  static Uint8List customers(List<CustomerSummary> customers) {
    final xlsx = XlsxWriter(sheetName: 'الزبائن')
      ..writeRow(const <Object?>[
        'الزبون',
        'الهاتف',
        'العنوان',
        'عدد الفواتير',
        'إجمالي المشتريات',
        'المدفوع',
        'الدين المتبقي',
      ]);
    for (final summary in customers) {
      xlsx.writeRow(<Object?>[
        summary.customer.name,
        summary.customer.phone,
        summary.customer.address,
        summary.invoiceCount,
        _amount(summary.totalPurchases),
        _amount(summary.totalPaid),
        _amount(summary.debt),
      ]);
    }
    return xlsx.build();
  }

  /// Money is kept as integer cents; Excel wants a decimal number.
  static double _amount(Money money) => money.cents / 100;
}
