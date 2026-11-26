import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:sqflite/sqflite.dart';

/// Runs the aggregate queries behind the reports screen.
class ReportRepository {
  ReportRepository(this._database, this._invoices, this._purchases);

  final AppDatabase _database;
  final InvoiceRepository _invoices;
  final PurchaseRepository _purchases;

  /// A range longer than this is charted per month instead of per day.
  static const int _maxDailyPoints = 62;

  Future<ReportData> load(DateRange range) async {
    final from = range.fromIso;
    final to = range.toIso;
    final byMonth = range.days > _maxDailyPoints;

    return ReportData(
      range: range,
      summary: await _summary(from, to),
      series: SalesPoint.fillGaps(
        range,
        await _series(from, to, byMonth: byMonth),
        byMonth: byMonth,
      ),
      groupedByMonth: byMonth,
      categories: await _categories(from, to),
      topItems: await _topItems(from, to),
      invoices: await _invoices.getInvoices(fromDate: from, toDate: to),
      purchases: await _purchases.getPurchases(fromDate: from, toDate: to),
    );
  }

  Future<ReportSummary> _summary(String from, String to) async {
    final db = _database.db;
    final sales = await db.rawQuery(
      'SELECT COUNT(*) AS invoice_count, '
      'IFNULL(SUM(total_cents), 0) AS sales_cents, '
      'IFNULL(SUM(profit_cents), 0) AS profit_cents, '
      'IFNULL(SUM(total_cents - paid_cents), 0) AS outstanding_cents '
      'FROM ${DbTables.invoices} WHERE invoice_date BETWEEN ? AND ?',
      <Object?>[from, to],
    );
    final collected = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT IFNULL(SUM(amount_cents), 0) FROM ${DbTables.payments} '
        'WHERE paid_date BETWEEN ? AND ?',
        <Object?>[from, to],
      ),
    );
    final buybacks = await db.rawQuery(
      'SELECT COUNT(*) AS purchase_count, '
      'IFNULL(SUM(total_cents), 0) AS purchases_cents, '
      'IFNULL(SUM(total_cents - paid_cents), 0) AS payables_cents '
      'FROM ${DbTables.purchases} WHERE purchase_date BETWEEN ? AND ?',
      <Object?>[from, to],
    );
    final paidToCustomers = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT IFNULL(SUM(amount_cents), 0) FROM ${DbTables.purchasePayments} '
        'WHERE paid_date BETWEEN ? AND ?',
        <Object?>[from, to],
      ),
    );
    final row = sales.first;
    final buyback = buybacks.first;
    return ReportSummary(
      invoiceCount: row.readInt('invoice_count'),
      sales: Money(row.readInt('sales_cents')),
      profit: Money(row.readInt('profit_cents')),
      collected: Money(collected ?? 0),
      outstanding: Money(row.readInt('outstanding_cents')),
      purchaseCount: buyback.readInt('purchase_count'),
      purchases: Money(buyback.readInt('purchases_cents')),
      paidToCustomers: Money(paidToCustomers ?? 0),
      payables: Money(buyback.readInt('payables_cents')),
    );
  }

  Future<List<SalesPoint>> _series(
    String from,
    String to, {
    required bool byMonth,
  }) async {
    final bucket = byMonth ? 'substr(invoice_date, 1, 7)' : 'invoice_date';
    final rows = await _database.db.rawQuery(
      'SELECT $bucket AS bucket, SUM(total_cents) AS sales_cents, '
      'SUM(profit_cents) AS profit_cents '
      'FROM ${DbTables.invoices} WHERE invoice_date BETWEEN ? AND ? '
      'GROUP BY bucket ORDER BY bucket',
      <Object?>[from, to],
    );
    return rows
        .map(
          (row) => SalesPoint(
            bucket: row.readString('bucket'),
            sales: Money(row.readInt('sales_cents')),
            profit: Money(row.readInt('profit_cents')),
          ),
        )
        .toList();
  }

  Future<List<CategorySales>> _categories(String from, String to) async {
    final rows = await _database.db.rawQuery(
      'SELECT l.category AS category, '
      'SUM(l.quantity * l.unit_price_cents) AS sales_cents, '
      'SUM(l.quantity * (l.unit_price_cents - l.unit_cost_cents)) AS profit_cents, '
      'SUM(l.quantity) AS pieces '
      'FROM ${DbTables.invoiceItems} l '
      'JOIN ${DbTables.invoices} i ON i.id = l.invoice_id '
      'WHERE i.invoice_date BETWEEN ? AND ? '
      'GROUP BY l.category ORDER BY sales_cents DESC',
      <Object?>[from, to],
    );
    return rows
        .map(
          (row) => CategorySales(
            category: row.readString('category'),
            sales: Money(row.readInt('sales_cents')),
            profit: Money(row.readInt('profit_cents')),
            pieces: row.readInt('pieces'),
          ),
        )
        .toList();
  }

  Future<List<TopItem>> _topItems(String from, String to) async {
    final rows = await _database.db.rawQuery(
      'SELECT l.item_name AS name, SUM(l.quantity) AS pieces, '
      'SUM(l.quantity * l.unit_price_cents) AS sales_cents '
      'FROM ${DbTables.invoiceItems} l '
      'JOIN ${DbTables.invoices} i ON i.id = l.invoice_id '
      'WHERE i.invoice_date BETWEEN ? AND ? '
      'GROUP BY l.item_name ORDER BY pieces DESC, sales_cents DESC LIMIT 10',
      <Object?>[from, to],
    );
    return rows
        .map(
          (row) => TopItem(
            name: row.readString('name'),
            pieces: row.readInt('pieces'),
            sales: Money(row.readInt('sales_cents')),
          ),
        )
        .toList();
  }
}
