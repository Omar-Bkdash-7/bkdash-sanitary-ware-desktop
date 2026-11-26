import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:sqflite/sqflite.dart';

/// The one number both settlement directions must agree on.
///
/// Positive: the customer owes the shop (sales still unpaid).
/// Negative: the shop owes the customer (purchases still unpaid, or returns
/// credited more than they still owed).
///
/// A return counts as the credit it gave minus the cash that went back with it:
/// the cash was handed to the customer, so it no longer settles his debt.
abstract final class CustomerBalanceQuery {
  static Future<Money> net(DatabaseExecutor database, int customerId) async {
    final rows = await database.rawQuery(
      'SELECT '
      '(SELECT IFNULL(SUM(total_cents - paid_cents), 0) '
      ' FROM ${DbTables.invoices} WHERE customer_id = ?) - '
      '(SELECT IFNULL(SUM(total_cents - paid_cents), 0) '
      ' FROM ${DbTables.purchases} WHERE customer_id = ?) - '
      '(SELECT IFNULL(SUM(total_cents - refund_cents), 0) '
      ' FROM ${DbTables.returns} WHERE customer_id = ?) AS net_cents',
      <Object?>[customerId, customerId, customerId],
    );
    return Money(rows.first.readInt('net_cents'));
  }
}
