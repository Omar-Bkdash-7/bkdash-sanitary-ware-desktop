import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_balance_query.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_allocator.dart';

/// Records money collected from customers against their debts.
class PaymentRepository {
  PaymentRepository(this._database, this._changes, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Clock _clock;

  /// Applies [amount] to the oldest unpaid invoices of the customer.
  ///
  /// Throws a `ValidationException` when [amount] is more than the debt.
  Future<void> receiveCustomerPayment({
    required int customerId,
    required Money amount,
    String note = '',
  }) async {
    final now = _clock();
    final paidAt = AppDates.isoDateTime(now);
    final paidDate = AppDates.isoDate(now);

    await _database.db.transaction((txn) async {
      final net = await CustomerBalanceQuery.net(txn, customerId);
      if (!net.isPositive) {
        throw const ValidationException('لا توجد ذمم مستحقة على هذا الزبون.');
      }
      if (amount > net) {
        throw ValidationException(
          'المبلغ أكبر من صافي المستحق على الزبون (${net.format()}).',
        );
      }

      final rows = await txn.rawQuery(
        'SELECT id, total_cents - paid_cents AS remaining_cents '
        'FROM ${DbTables.invoices} '
        'WHERE customer_id = ? AND total_cents > paid_cents '
        'ORDER BY invoice_date, id',
        <Object?>[customerId],
      );
      final outstanding = rows
          .map(
            (row) => OutstandingInvoice(
              invoiceId: row.readInt('id'),
              remaining: Money(row.readInt('remaining_cents')),
            ),
          )
          .toList();
      final allocations = PaymentAllocator.allocate(outstanding, amount);

      final receiptId = await txn
          .insert(DbTables.customerReceipts, <String, Object?>{
            'customer_id': customerId,
            'amount_cents': amount.cents,
            'note': note.trim(),
            'paid_at': paidAt,
            'paid_date': paidDate,
          });
      for (final allocation in allocations) {
        await txn.insert(DbTables.payments, <String, Object?>{
          'invoice_id': allocation.invoiceId,
          'receipt_id': receiptId,
          'amount_cents': allocation.amount.cents,
          'paid_at': paidAt,
          'paid_date': paidDate,
        });
        await txn.rawUpdate(
          'UPDATE ${DbTables.invoices} SET paid_cents = paid_cents + ? '
          'WHERE id = ?',
          <Object?>[allocation.amount.cents, allocation.invoiceId],
        );
      }
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.payment);
  }

  /// Payments received from [customerId], newest first.
  Future<List<CustomerReceipt>> receiptsFor(int customerId) async {
    final rows = await _database.db.query(
      DbTables.customerReceipts,
      where: 'customer_id = ?',
      whereArgs: <Object?>[customerId],
      orderBy: 'id DESC',
    );
    return rows.map(CustomerReceipt.fromRow).toList();
  }
}
