import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';

/// Reads and writes the registered customers.
class CustomerRepository {
  CustomerRepository(this._database, this._changes, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Clock _clock;

  /// Sales and purchases are aggregated separately: joining both tables to
  /// `customers` directly would multiply every invoice by every purchase.
  static const String _summarySelect = '''
WITH sales AS (
  SELECT customer_id,
         COUNT(*) AS invoice_count,
         IFNULL(SUM(total_cents), 0) AS sales_cents,
         IFNULL(SUM(paid_cents), 0) AS sales_paid_cents
  FROM invoices
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
),
buybacks AS (
  SELECT customer_id,
         COUNT(*) AS purchase_count,
         IFNULL(SUM(total_cents), 0) AS purchases_cents,
         IFNULL(SUM(paid_cents), 0) AS purchases_paid_cents
  FROM purchases
  GROUP BY customer_id
),
cancellations AS (
  SELECT customer_id,
         COUNT(*) AS return_count,
         IFNULL(SUM(total_cents), 0) AS returns_cents,
         IFNULL(SUM(refund_cents), 0) AS refunded_cents
  FROM returns
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
)
SELECT c.id, c.name, c.phone, c.address, c.notes,
       IFNULL(s.invoice_count, 0) AS invoice_count,
       IFNULL(s.sales_cents, 0) AS sales_cents,
       IFNULL(s.sales_paid_cents, 0) AS sales_paid_cents,
       IFNULL(b.purchase_count, 0) AS purchase_count,
       IFNULL(b.purchases_cents, 0) AS purchases_cents,
       IFNULL(b.purchases_paid_cents, 0) AS purchases_paid_cents,
       IFNULL(r.return_count, 0) AS return_count,
       IFNULL(r.returns_cents, 0) AS returns_cents,
       IFNULL(r.refunded_cents, 0) AS refunded_cents
FROM customers c
LEFT JOIN sales s ON s.customer_id = c.id
LEFT JOIN buybacks b ON b.customer_id = c.id
LEFT JOIN cancellations r ON r.customer_id = c.id
''';

  /// Every customer with his totals; the biggest net debtors come first.
  Future<List<CustomerSummary>> getAllWithSummary() async {
    final rows = await _database.db.rawQuery('''
$_summarySelect
ORDER BY ((sales_cents - sales_paid_cents) -
          (purchases_cents - purchases_paid_cents) -
          (returns_cents - refunded_cents)) DESC,
         c.name COLLATE NOCASE
''');
    return rows.map(CustomerSummary.fromRow).toList();
  }

  Future<CustomerSummary?> getSummary(int id) async {
    final rows = await _database.db.rawQuery(
      '$_summarySelect WHERE c.id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : CustomerSummary.fromRow(rows.first);
  }

  Future<Customer> create(CustomerInput input) async {
    input.validate();
    final id = await _database.db.insert(DbTables.customers, <String, Object?>{
      ..._toRow(input),
      'created_at': AppDates.isoDateTime(_clock()),
    });
    _changes.markChanged();
    _changes.reportWrite(DataWrite.customers);
    return Customer(
      id: id,
      name: input.name.trim(),
      phone: input.phone.trim(),
      address: input.address.trim(),
      notes: input.notes.trim(),
    );
  }

  Future<void> update(int id, CustomerInput input) async {
    input.validate();
    final changed = await _database.db.update(
      DbTables.customers,
      _toRow(input),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (changed == 0) throw const NotFoundException('الزبون غير موجود.');
    // Old invoices keep the name they were issued with; only new ones use it.
    _changes.markChanged();
    _changes.reportWrite(DataWrite.customers);
  }

  /// A customer who has invoices or purchases can not be deleted: either would
  /// erase part of his account history and of the balance he is owed.
  ///
  /// The checks and the delete run in one transaction: a document saved from
  /// another screen can never slip in between them.
  Future<void> delete(int id) async {
    await _database.db.transaction((txn) async {
      final existing = await txn.query(
        DbTables.customers,
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (existing.isEmpty) throw const NotFoundException('الزبون غير موجود.');
      final invoices = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM ${DbTables.invoices} '
        'WHERE customer_id = ?',
        <Object?>[id],
      );
      final invoiceCount = (invoices.first['count'] as int?) ?? 0;
      if (invoiceCount > 0) {
        throw const ConflictException(
          'لا يمكن حذف زبون لديه فواتير مسجّلة، لأن ذلك يُفقد سجلّ ديونه.',
        );
      }
      final purchases = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM ${DbTables.purchases} '
        'WHERE customer_id = ?',
        <Object?>[id],
      );
      final purchaseCount = (purchases.first['count'] as int?) ?? 0;
      if (purchaseCount > 0) {
        throw const ConflictException(
          'لا يمكن حذف زبون لديه عمليات شراء مسجّلة، لأن ذلك يُفقد سجلّ '
          'المبالغ المستحقة له.',
        );
      }
      await txn.delete(
        DbTables.customers,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
    _changes.markChanged();
    _changes.reportWrite(DataWrite.customers);
  }

  Map<String, Object?> _toRow(CustomerInput input) => <String, Object?>{
    'name': input.name.trim(),
    'phone': input.phone.trim(),
    'address': input.address.trim(),
    'notes': input.notes.trim(),
  };
}
