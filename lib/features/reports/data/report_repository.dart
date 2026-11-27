import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:sqflite/sqflite.dart';

/// Runs the aggregate queries behind the reports screen.
///
/// Every sales number is net of the returns of the same period, so the reports
/// always add up to what the shop actually kept. Returns are their own
/// documents: they never rewrite the invoice that sold the pieces.
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
    // Every payout is cash that left the shop, including the one that settles
    // the credit of an old return (it is not tied to a purchase). The payment
    // made when the purchase itself was saved has no payout row.
    final paidToCustomers = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT (SELECT IFNULL(SUM(amount_cents), 0) '
        ' FROM ${DbTables.customerPayouts} WHERE paid_date BETWEEN ? AND ?) + '
        ' (SELECT IFNULL(SUM(amount_cents), 0) '
        ' FROM ${DbTables.purchasePayments} '
        ' WHERE payout_id IS NULL AND paid_date BETWEEN ? AND ?) AS total',
        <Object?>[from, to, from, to],
      ),
    );
    final returns = await db.rawQuery(
      'SELECT COUNT(*) AS return_count, '
      'IFNULL(SUM(total_cents), 0) AS credits_cents, '
      'IFNULL(SUM(refund_cents), 0) AS refunds_cents '
      'FROM ${DbTables.returns} WHERE return_date BETWEEN ? AND ?',
      <Object?>[from, to],
    );
    final returnedProfit = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT IFNULL(SUM(li.quantity * '
        '(li.unit_price_cents - li.unit_cost_cents)), 0) '
        'FROM ${DbTables.returnItems} li '
        'JOIN ${DbTables.returns} r ON r.id = li.return_id '
        'WHERE r.return_date BETWEEN ? AND ?',
        <Object?>[from, to],
      ),
    );
    // A return cancels part of the debt of the invoice it belongs to, even when
    // it was made in a later period.
    final creditedOnPeriodInvoices = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT IFNULL(SUM(r.total_cents - r.refund_cents), 0) '
        'FROM ${DbTables.returns} r '
        'JOIN ${DbTables.invoices} i ON i.id = r.invoice_id '
        'WHERE i.invoice_date BETWEEN ? AND ?',
        <Object?>[from, to],
      ),
    );
    final row = sales.first;
    final buyback = buybacks.first;
    final returned = returns.first;
    return ReportSummary(
      invoiceCount: row.readInt('invoice_count'),
      sales: Money(row.readInt('sales_cents')),
      profit: Money(row.readInt('profit_cents')),
      collected: Money(collected ?? 0),
      outstanding: Money(
        row.readInt('outstanding_cents') - (creditedOnPeriodInvoices ?? 0),
      ),
      purchaseCount: buyback.readInt('purchase_count'),
      purchases: Money(buyback.readInt('purchases_cents')),
      paidToCustomers: Money(paidToCustomers ?? 0),
      payables: Money(buyback.readInt('payables_cents')),
      returnCount: returned.readInt('return_count'),
      returns: Money(returned.readInt('credits_cents')),
      refundedToCustomers: Money(returned.readInt('refunds_cents')),
      returnedProfit: Money(returnedProfit ?? 0),
    );
  }

  Future<List<SalesPoint>> _series(
    String from,
    String to, {
    required bool byMonth,
  }) async {
    final db = _database.db;
    final invoiceBucket =
        byMonth ? 'substr(invoice_date, 1, 7)' : 'invoice_date';
    final invoices = await db.rawQuery(
      'SELECT $invoiceBucket AS bucket, SUM(total_cents) AS sales_cents, '
      'SUM(profit_cents) AS profit_cents '
      'FROM ${DbTables.invoices} WHERE invoice_date BETWEEN ? AND ? '
      'GROUP BY bucket ORDER BY bucket',
      <Object?>[from, to],
    );
    final returnBucket = byMonth ? 'substr(return_date, 1, 7)' : 'return_date';
    final credits = await db.rawQuery(
      'SELECT $returnBucket AS bucket, SUM(total_cents) AS credits_cents '
      'FROM ${DbTables.returns} WHERE return_date BETWEEN ? AND ? '
      'GROUP BY bucket',
      <Object?>[from, to],
    );
    final returnProfit = await db.rawQuery(
      'SELECT $returnBucket AS bucket, '
      'SUM(li.quantity * (li.unit_price_cents - li.unit_cost_cents)) '
      'AS profit_cents '
      'FROM ${DbTables.returnItems} li '
      'JOIN ${DbTables.returns} r ON r.id = li.return_id '
      'WHERE r.return_date BETWEEN ? AND ? GROUP BY bucket',
      <Object?>[from, to],
    );

    final sales = <String, int>{
      for (final row in invoices) row.readString('bucket'): row.readInt('sales_cents'),
    };
    final profits = <String, int>{
      for (final row in invoices)
        row.readString('bucket'): row.readInt('profit_cents'),
    };
    final creditByBucket = <String, int>{
      for (final row in credits)
        row.readString('bucket'): row.readInt('credits_cents'),
    };
    final profitByBucket = <String, int>{
      for (final row in returnProfit)
        row.readString('bucket'): row.readInt('profit_cents'),
    };
    final buckets = <String>{
      ...sales.keys,
      ...creditByBucket.keys,
    }.toList()..sort();
    return <SalesPoint>[
      for (final bucket in buckets)
        SalesPoint(
          bucket: bucket,
          sales: Money((sales[bucket] ?? 0) - (creditByBucket[bucket] ?? 0)),
          profit: Money((profits[bucket] ?? 0) - (profitByBucket[bucket] ?? 0)),
        ),
    ];
  }

  Future<List<CategorySales>> _categories(String from, String to) async {
    final rows = await _database.db.rawQuery(
      'SELECT category, SUM(sales_cents) AS sales_cents, '
      'SUM(profit_cents) AS profit_cents, SUM(pieces) AS pieces FROM ('
      'SELECT l.category AS category, '
      'SUM(l.quantity * l.unit_price_cents) AS sales_cents, '
      'SUM(l.quantity * (l.unit_price_cents - l.unit_cost_cents)) '
      'AS profit_cents, SUM(l.quantity) AS pieces '
      'FROM ${DbTables.invoiceItems} l '
      'JOIN ${DbTables.invoices} i ON i.id = l.invoice_id '
      'WHERE i.invoice_date BETWEEN ? AND ? GROUP BY l.category '
      'UNION ALL '
      'SELECT li.category, -SUM(li.quantity * li.unit_price_cents), '
      '-SUM(li.quantity * (li.unit_price_cents - li.unit_cost_cents)), '
      '-SUM(li.quantity) '
      'FROM ${DbTables.returnItems} li '
      'JOIN ${DbTables.returns} r ON r.id = li.return_id '
      'WHERE r.return_date BETWEEN ? AND ? GROUP BY li.category'
      ') GROUP BY category HAVING SUM(sales_cents) > 0 '
      'ORDER BY sales_cents DESC',
      <Object?>[from, to, from, to],
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
      'SELECT name, SUM(pieces) AS pieces, SUM(sales_cents) AS sales_cents '
      'FROM ('
      'SELECT l.item_name AS name, SUM(l.quantity) AS pieces, '
      'SUM(l.quantity * l.unit_price_cents) AS sales_cents '
      'FROM ${DbTables.invoiceItems} l '
      'JOIN ${DbTables.invoices} i ON i.id = l.invoice_id '
      'WHERE i.invoice_date BETWEEN ? AND ? GROUP BY l.item_name '
      'UNION ALL '
      'SELECT li.item_name, -SUM(li.quantity), '
      '-SUM(li.quantity * li.unit_price_cents) '
      'FROM ${DbTables.returnItems} li '
      'JOIN ${DbTables.returns} r ON r.id = li.return_id '
      'WHERE r.return_date BETWEEN ? AND ? GROUP BY li.item_name'
      ') GROUP BY name HAVING SUM(pieces) > 0 '
      'ORDER BY pieces DESC, sales_cents DESC LIMIT 10',
      <Object?>[from, to, from, to],
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
