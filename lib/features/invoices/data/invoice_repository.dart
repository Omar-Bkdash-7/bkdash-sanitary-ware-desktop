import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_line_export.dart';
import 'package:sqflite/sqflite.dart';

/// Issues and reads invoices.
class InvoiceRepository {
  InvoiceRepository(this._database, this._changes, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Clock _clock;

  /// Saves [draft] as a new invoice and returns its number.
  ///
  /// Everything happens in one transaction: the stock is reduced, the invoice
  /// and its lines are written and the payment is recorded - or nothing is
  /// changed at all (for example when the stock is not enough).
  Future<int> create(InvoiceDraft draft) async {
    draft.validate();
    final now = _clock();
    final createdAt = AppDates.isoDateTime(now);
    final date = AppDates.isoDate(now);
    final total = draft.total;
    final paid = draft.paid;

    final invoiceId = await _database.db.transaction((txn) async {
      for (final line in draft.lines) {
        // Atomic: reduces the stock only when enough pieces are left.
        final changed = await txn.rawUpdate(
          'UPDATE ${DbTables.items} SET quantity = quantity - ? '
          'WHERE id = ? AND quantity >= ?',
          <Object?>[line.quantity, line.itemId, line.quantity],
        );
        if (changed == 0) {
          final rows = await txn.query(
            DbTables.items,
            columns: <String>['name', 'quantity'],
            where: 'id = ?',
            whereArgs: <Object?>[line.itemId],
          );
          if (rows.isEmpty) {
            throw NotFoundException('الصنف "${line.itemName}" لم يعد موجوداً.');
          }
          throw InsufficientStockException(
            itemName: rows.first['name']! as String,
            available: rows.first['quantity']! as int,
            requested: line.quantity,
          );
        }
      }

      final id = await txn.insert(DbTables.invoices, <String, Object?>{
        'customer_id': draft.customer?.id,
        'customer_name':
            draft.customer?.name ?? AppConstants.walkInCustomerName,
        'customer_phone': draft.customer?.phone ?? '',
        'payment_method': draft.paymentMethod.key,
        'invoice_date': date,
        'created_at': createdAt,
        'total_cents': total.cents,
        'paid_cents': paid.cents,
        'profit_cents': draft.profit.cents,
        'notes': draft.notes.trim(),
      });

      final lines = txn.batch();
      for (final line in draft.lines) {
        lines.insert(DbTables.invoiceItems, <String, Object?>{
          'invoice_id': id,
          'item_id': line.itemId,
          'item_name': line.itemName,
          'category': line.category,
          'sku': line.sku,
          'container': line.container,
          'unit': line.unit,
          'quantity': line.quantity,
          'unit_cost_cents': line.unitCost.cents,
          'unit_price_cents': line.unitPrice.cents,
        });
      }
      await lines.commit(noResult: true);

      if (paid.isPositive) {
        await txn.insert(DbTables.payments, <String, Object?>{
          'invoice_id': id,
          'amount_cents': paid.cents,
          'paid_at': createdAt,
          'paid_date': date,
        });
      }
      return id;
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.invoice, invoiceId: invoiceId);
    return invoiceId;
  }

  /// Rewrites the saved invoice [id] from [draft].
  ///
  /// The stock of the old lines is given back and the stock of the new lines is
  /// taken inside one transaction, so a refused edit (not enough pieces) leaves
  /// the invoice, the stock and the customer balance exactly as they were. The
  /// invoice date and its number never change - only what was sold and how it
  /// was paid.
  Future<void> update(int id, InvoiceDraft draft) async {
    draft.validate();
    await _database.db.transaction((txn) async {
      final header = await txn.query(
        DbTables.invoices,
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (header.isEmpty) throw const NotFoundException('الفاتورة غير موجودة.');
      await _ensureNoLaterPayments(txn, id);
      await _ensureNoReturns(txn, id);

      await _restoreStock(txn, id);
      await _takeStock(txn, draft.lines);

      await txn.update(
        DbTables.invoices,
        <String, Object?>{
          'customer_id': draft.customer?.id,
          'customer_name':
              draft.customer?.name ?? AppConstants.walkInCustomerName,
          'customer_phone': draft.customer?.phone ?? '',
          'payment_method': draft.paymentMethod.key,
          'total_cents': draft.total.cents,
          'paid_cents': draft.paid.cents,
          'profit_cents': draft.profit.cents,
          'notes': draft.notes.trim(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );

      await txn.delete(
        DbTables.invoiceItems,
        where: 'invoice_id = ?',
        whereArgs: <Object?>[id],
      );
      await _insertLines(txn, id, draft.lines);

      // The payment made when the invoice was issued is part of the invoice;
      // it is rewritten with it, dated as the sale so the reports stay right.
      await txn.delete(
        DbTables.payments,
        where: 'invoice_id = ?',
        whereArgs: <Object?>[id],
      );
      if (draft.paid.isPositive) {
        await txn.insert(DbTables.payments, <String, Object?>{
          'invoice_id': id,
          'amount_cents': draft.paid.cents,
          'paid_at': header.first['created_at'],
          'paid_date': header.first['invoice_date'],
        });
      }
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.invoiceUpdated, invoiceId: id);
  }

  /// Deletes the invoice [id] as if it had never been issued.
  ///
  /// Every piece goes back to the stock, its payment disappears and the
  /// customer owes what he owed before it - all in one transaction.
  Future<void> delete(int id) async {
    await _database.db.transaction((txn) async {
      final header = await txn.query(
        DbTables.invoices,
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (header.isEmpty) throw const NotFoundException('الفاتورة غير موجودة.');
      await _ensureNoLaterPayments(txn, id);
      await _ensureNoReturns(txn, id);

      await _restoreStock(txn, id);
      await txn.delete(
        DbTables.payments,
        where: 'invoice_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        DbTables.invoiceItems,
        where: 'invoice_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        DbTables.invoices,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.invoiceDeleted, invoiceId: id);
  }

  /// Gives the pieces of the saved invoice [id] back to the stock.
  ///
  /// A product that was deleted from the inventory since the sale is skipped:
  /// [DbTables.invoiceItems] keeps its own copy of the name and the prices.
  Future<void> _restoreStock(DatabaseExecutor txn, int id) async {
    final lines = await txn.query(
      DbTables.invoiceItems,
      columns: <String>['item_id', 'quantity'],
      where: 'invoice_id = ?',
      whereArgs: <Object?>[id],
    );
    for (final line in lines) {
      final itemId = line['item_id'] as int?;
      if (itemId == null) continue;
      await txn.rawUpdate(
        'UPDATE ${DbTables.items} SET quantity = quantity + ? WHERE id = ?',
        <Object?>[line['quantity'], itemId],
      );
    }
  }

  /// Reduces the stock of [lines]; throws when a product does not have enough.
  Future<void> _takeStock(DatabaseExecutor txn, List<InvoiceLine> lines) async {
    for (final line in lines) {
      final changed = await txn.rawUpdate(
        'UPDATE ${DbTables.items} SET quantity = quantity - ? '
        'WHERE id = ? AND quantity >= ?',
        <Object?>[line.quantity, line.itemId, line.quantity],
      );
      if (changed == 0) {
        final rows = await txn.query(
          DbTables.items,
          columns: <String>['name', 'quantity'],
          where: 'id = ?',
          whereArgs: <Object?>[line.itemId],
        );
        if (rows.isEmpty) {
          throw NotFoundException('الصنف "${line.itemName}" لم يعد موجوداً.');
        }
        throw InsufficientStockException(
          itemName: rows.first['name']! as String,
          available: rows.first['quantity']! as int,
          requested: line.quantity,
        );
      }
    }
  }

  Future<void> _insertLines(
    DatabaseExecutor txn,
    int invoiceId,
    List<InvoiceLine> lines,
  ) async {
    final batch = txn.batch();
    for (final line in lines) {
      batch.insert(DbTables.invoiceItems, <String, Object?>{
        'invoice_id': invoiceId,
        'item_id': line.itemId,
        'item_name': line.itemName,
        'category': line.category,
        'sku': line.sku,
        'container': line.container,
        'unit': line.unit,
        'quantity': line.quantity,
        'unit_cost_cents': line.unitCost.cents,
        'unit_price_cents': line.unitPrice.cents,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Refuses to touch an invoice that already has returns.
  ///
  /// The returned pieces are back in the stock and their credit is part of the
  /// customer's balance; rewriting or deleting the invoice behind them would
  /// count those pieces twice. Deleting the returns first makes the invoice
  /// editable again.
  static Future<void> _ensureNoReturns(DatabaseExecutor txn, int id) async {
    final rows = await txn.query(
      DbTables.returns,
      columns: <String>['id'],
      where: 'invoice_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const ConflictException(
        'لا يمكن تعديل أو حذف فاتورة صُدر عنها مرتجع، لأن القطع عادت إلى '
        'المخزون والرصيد تغيّر. احذف المرتجع أولاً ثم عُدّل الفاتورة.',
      );
    }
  }

  /// Refuses to touch an invoice that money was later collected against.
  ///
  /// Such a payment belongs to the customer's ledger (it may cover several
  /// invoices), so removing the invoice behind his back would break his
  /// balance and the collected-cash reports.
  static Future<void> _ensureNoLaterPayments(
    DatabaseExecutor txn,
    int id,
  ) async {
    final rows = await txn.query(
      DbTables.payments,
      columns: <String>['id'],
      where: 'invoice_id = ? AND receipt_id IS NOT NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const ConflictException(
        'لا يمكن تعديل أو حذف فاتورة سُدِّد جزء منها لاحقاً من ذمة الزبون، '
        'لأن المبلغ مسجّل في حسابه. الفواتير المدفوعة وقت الإصدار فقط '
        'يمكن تعديلها أو حذفها.',
      );
    }
  }

  /// What the customer still owed on his older invoices, before [invoiceId].
  ///
  /// Printed on the invoice so the customer sees one total, not only the part
  /// of this sale. A walk-in invoice (no customer) has no earlier debt.
  Future<Money> previousDebt({
    required int invoiceId,
    required int? customerId,
  }) async {
    if (customerId == null) return Money.zero;
    final rows = await _database.db.rawQuery(
      'SELECT '
      '(SELECT IFNULL(SUM(total_cents - paid_cents), 0) '
      ' FROM ${DbTables.invoices} WHERE customer_id = ? AND id < ?) - '
      '(SELECT IFNULL(SUM(r.total_cents - r.refund_cents), 0) '
      ' FROM ${DbTables.returns} r '
      ' JOIN ${DbTables.invoices} i ON i.id = r.invoice_id '
      ' WHERE i.customer_id = ? AND i.id < ?) AS debt',
      <Object?>[customerId, invoiceId, customerId, invoiceId],
    );
    return Money((rows.first['debt'] as int?) ?? 0);
  }

  /// Invoices, newest first. [fromDate] / [toDate] are "yyyy-MM-dd" (inclusive).
  Future<List<Invoice>> getInvoices({
    int? customerId,
    String? fromDate,
    String? toDate,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      conditions.add('customer_id = ?');
      args.add(customerId);
    }
    if (fromDate != null) {
      conditions.add('invoice_date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      conditions.add('invoice_date <= ?');
      args.add(toDate);
    }
    final rows = await _database.db.query(
      DbTables.invoices,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
    );
    return rows.map(Invoice.fromRow).toList();
  }

  Future<InvoiceDetails?> getDetails(int id) async {
    final db = _database.db;
    final headers = await db.query(
      DbTables.invoices,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (headers.isEmpty) return null;
    final lines = await db.query(
      DbTables.invoiceItems,
      where: 'invoice_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id',
    );
    final payments = await db.query(
      DbTables.payments,
      where: 'invoice_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id',
    );
    return InvoiceDetails(
      invoice: Invoice.fromRow(headers.first),
      lines: lines.map(InvoiceLineRecord.fromRow).toList(),
      payments: payments.map(PaymentRecord.fromRow).toList(),
    );
  }

  /// Every product line of every invoice (used by the CSV export).
  Future<List<InvoiceLineExport>> getAllLines() async {
    final rows = await _database.db.rawQuery(
      'SELECT l.*, i.invoice_date, i.customer_name '
      'FROM ${DbTables.invoiceItems} l '
      'JOIN ${DbTables.invoices} i ON i.id = l.invoice_id '
      'ORDER BY l.invoice_id, l.id',
    );
    return rows
        .map(
          (row) => InvoiceLineExport(
            invoiceId: row['invoice_id']! as int,
            invoiceDate: row['invoice_date']! as String,
            customerName: row['customer_name']! as String,
            line: InvoiceLineRecord.fromRow(row),
          ),
        )
        .toList();
  }
}
