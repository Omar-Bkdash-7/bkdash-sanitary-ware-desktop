import 'dart:io';

import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/backup/data/xlsx_exports.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/returns/data/return_repository.dart';
import 'package:path/path.dart' as p;

/// Writes the Excel (`.xlsx`) exports to files.
class ExportService {
  ExportService({
    required ItemRepository items,
    required InvoiceRepository invoices,
    required PurchaseRepository purchases,
    required ReturnRepository returns,
    required CustomerRepository customers,
    required Future<Directory> Function() exportDirectory,
    Clock? clock,
  }) : _items = items,
       _invoices = invoices,
       _purchases = purchases,
       _returns = returns,
       _customers = customers,
       _exportDirectory = exportDirectory,
       _clock = clock ?? DateTime.now;

  final ItemRepository _items;
  final InvoiceRepository _invoices;
  final PurchaseRepository _purchases;
  final ReturnRepository _returns;
  final CustomerRepository _customers;
  final Future<Directory> Function() _exportDirectory;
  final Clock _clock;

  Future<File> exportInventory() async =>
      _write('inventory', XlsxExports.inventory(await _items.getAll()));

  Future<File> exportInvoices() async =>
      _write('invoices', XlsxExports.invoices(await _invoices.getInvoices()));

  Future<File> exportInvoiceLines() async => _write(
    'invoice_lines',
    XlsxExports.invoiceLines(await _invoices.getAllLines()),
  );

  Future<File> exportPurchases() async => _write(
    'purchases',
    XlsxExports.purchases(await _purchases.getPurchases()),
  );

  Future<File> exportPurchaseLines() async => _write(
    'purchase_lines',
    XlsxExports.purchaseLines(await _purchases.getAllLines()),
  );

  Future<File> exportReturns() async =>
      _write('returns', XlsxExports.returns(await _returns.getAll()));

  Future<File> exportReturnLines() async => _write(
    'return_lines',
    XlsxExports.returnLines(await _returns.getAll()),
  );

  Future<File> exportCustomers() async => _write(
    'customers',
    XlsxExports.customers(await _customers.getAllWithSummary()),
  );

  Future<File> _write(String baseName, List<int> content) async {
    final folder = await _exportDirectory();
    await folder.create(recursive: true);
    final file = File(
      p.join(
        folder.path,
        'bkdash_${baseName}_${AppDates.fileStamp(_clock())}.xlsx',
      ),
    );
    return file.writeAsBytes(content, flush: true);
  }
}
