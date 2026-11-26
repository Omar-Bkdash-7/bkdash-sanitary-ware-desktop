import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/csv_writer.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_line_export.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_line_export.dart';

/// Builds the CSV text of each export (no files, no database: easy to test).
abstract final class CsvExports {
  static String inventory(List<Item> items) {
    final csv = CsvWriter()
      ..writeRow(<Object?>[
        'الصنف',
        'اسم المادة',
        'الرمز',
        'الحاوية',
        'الوحدة',
        'سعر التكلفة',
        'سعر البيع',
        'الكمية',
        'قيمة المخزون (تكلفة)',
        'قيمة المخزون (بيع)',
        'ملاحظات',
      ]);
    for (final item in items) {
      csv.writeRow(<Object?>[
        item.category,
        item.name,
        item.sku,
        item.container,
        item.unit,
        item.cost.toPlainString(),
        item.price.toPlainString(),
        item.quantity,
        item.stockCostValue.toPlainString(),
        item.stockSaleValue.toPlainString(),
        item.notes,
      ]);
    }
    return csv.build();
  }

  static String invoices(List<Invoice> invoices) {
    final csv = CsvWriter()
      ..writeRow(<Object?>[
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
      csv.writeRow(<Object?>[
        invoice.id,
        AppDates.displayIso(invoice.invoiceDate),
        AppDates.timeIso(invoice.createdAt),
        invoice.customerName,
        invoice.customerPhone,
        invoice.paymentMethod.label,
        invoice.total.toPlainString(),
        invoice.paid.toPlainString(),
        invoice.remaining.toPlainString(),
        invoice.profit.toPlainString(),
        invoice.notes,
      ]);
    }
    return csv.build();
  }

  static String invoiceLines(List<InvoiceLineExport> lines) {
    final csv = CsvWriter()
      ..writeRow(<Object?>[
        'رقم الفاتورة',
        'التاريخ',
        'الزبون',
        'الصنف',
        'اسم المادة',
        'الرمز',
        'الحاوية',
        'الوحدة',
        'الكمية',
        'سعر البيع',
        'إجمالي السطر',
        'ربح السطر',
      ]);
    for (final entry in lines) {
      final line = entry.line;
      csv.writeRow(<Object?>[
        entry.invoiceId,
        AppDates.displayIso(entry.invoiceDate),
        entry.customerName,
        line.category,
        line.itemName,
        line.sku,
        line.container,
        line.unit,
        line.quantity,
        line.unitPrice.toPlainString(),
        line.lineTotal.toPlainString(),
        line.lineProfit.toPlainString(),
      ]);
    }
    return csv.build();
  }

  static String purchases(List<Purchase> purchases) {
    final csv = CsvWriter()
      ..writeRow(<Object?>[
        'رقم الشراء',
        'التاريخ',
        'الوقت',
        'الزبون',
        'الهاتف',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'ملاحظات',
      ]);
    for (final purchase in purchases) {
      csv.writeRow(<Object?>[
        purchase.id,
        AppDates.displayIso(purchase.purchaseDate),
        AppDates.timeIso(purchase.createdAt),
        purchase.customerName,
        purchase.customerPhone,
        purchase.total.toPlainString(),
        purchase.paid.toPlainString(),
        purchase.remaining.toPlainString(),
        purchase.notes,
      ]);
    }
    return csv.build();
  }

  static String purchaseLines(List<PurchaseLineExport> lines) {
    final csv = CsvWriter()
      ..writeRow(<Object?>[
        'رقم الشراء',
        'التاريخ',
        'الزبون',
        'الصنف',
        'اسم المادة',
        'الرمز',
        'الحاوية',
        'الوحدة',
        'الكمية',
        'سعر الشراء',
        'إجمالي السطر',
      ]);
    for (final entry in lines) {
      final line = entry.line;
      csv.writeRow(<Object?>[
        entry.purchaseId,
        AppDates.displayIso(entry.purchaseDate),
        entry.customerName,
        line.category,
        line.itemName,
        line.sku,
        line.container,
        line.unit,
        line.quantity,
        line.unitCost.toPlainString(),
        line.lineTotal.toPlainString(),
      ]);
    }
    return csv.build();
  }

  static String customers(List<CustomerSummary> customers) {
    final csv = CsvWriter()
      ..writeRow(<Object?>[
        'الزبون',
        'الهاتف',
        'العنوان',
        'عدد الفواتير',
        'إجمالي المبيعات',
        'المقبوض',
        'عدد عمليات الشراء',
        'إجمالي المشتريات من الزبون',
        'المدفوع للزبون',
        'صافي الرصيد',
      ]);
    for (final summary in customers) {
      csv.writeRow(<Object?>[
        summary.customer.name,
        summary.customer.phone,
        summary.customer.address,
        summary.invoiceCount,
        summary.totalSales.toPlainString(),
        summary.totalReceived.toPlainString(),
        summary.purchaseCount,
        summary.totalPurchases.toPlainString(),
        summary.totalPaidToCustomer.toPlainString(),
        summary.netBalance.toPlainString(),
      ]);
    }
    return csv.build();
  }
}
