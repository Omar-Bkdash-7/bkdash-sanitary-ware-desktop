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

  static const String _summarySelect = '''
SELECT c.id, c.name, c.phone, c.address, c.notes,
       COUNT(i.id) AS invoice_count,
       IFNULL(SUM(i.total_cents), 0) AS total_cents,
       IFNULL(SUM(i.paid_cents), 0) AS paid_cents
FROM customers c
LEFT JOIN invoices i ON i.customer_id = c.id
''';

  /// Every customer with his totals; the biggest debtors come first.
  Future<List<CustomerSummary>> getAllWithSummary() async {
    final rows = await _database.db.rawQuery('''
$_summarySelect
GROUP BY c.id
ORDER BY (IFNULL(SUM(i.total_cents), 0) - IFNULL(SUM(i.paid_cents), 0)) DESC,
         c.name COLLATE NOCASE
''');
    return rows.map(CustomerSummary.fromRow).toList();
  }

  Future<CustomerSummary?> getSummary(int id) async {
    final rows = await _database.db.rawQuery(
      '$_summarySelect WHERE c.id = ? GROUP BY c.id',
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

  /// A customer who has invoices can not be deleted (it would erase the history
  /// of his debts).
  ///
  /// The check and the delete run in one transaction: an invoice saved from
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
