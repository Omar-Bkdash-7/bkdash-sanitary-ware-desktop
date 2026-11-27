import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';
import 'package:sqflite/sqflite.dart';

/// Records returned pieces against the invoice that sold them.
///
/// A return is a separate document: the invoice is never rewritten, so the
/// price the customer was charged that day stays the price of the credit. The
/// pieces go back to the inventory row they were taken from (same container),
/// and the customer's balance drops by the credit that was not handed back as
/// cash.
class ReturnRepository {
  ReturnRepository(this._database, this._changes, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Clock _clock;

  /// Every line of [invoiceId] with the pieces that can still come back.
  Future<List<ReturnableLine>> returnableLines(int invoiceId) async {
    final rows = await _returnableRows(_database.db, invoiceId);
    return rows
        .map(
          (row) => ReturnableLine(
            invoiceItemId: row.readInt('id'),
            line: InvoiceLineRecord.fromRow(row),
            returned: row.readInt('returned'),
          ),
        )
        .toList();
  }

  /// The returns of [invoiceId], newest first, with their lines.
  Future<List<ReturnRecord>> returnsForInvoice(int invoiceId) async {
    final db = _database.db;
    final headers = await db.query(
      DbTables.returns,
      where: 'invoice_id = ?',
      whereArgs: <Object?>[invoiceId],
      orderBy: 'id DESC',
    );
    if (headers.isEmpty) return const <ReturnRecord>[];
    final lines = await db.query(
      DbTables.returnItems,
      where: 'return_id IN (SELECT id FROM ${DbTables.returns} '
          'WHERE invoice_id = ?)',
      whereArgs: <Object?>[invoiceId],
      orderBy: 'id',
    );
    final byReturn = <int, List<ReturnLineRecord>>{};
    for (final row in lines) {
      final returnId = row.readInt('return_id');
      (byReturn[returnId] ??= <ReturnLineRecord>[])
          .add(ReturnLineRecord.fromRow(row));
    }
    return headers
        .map(
          (row) => ReturnRecord.fromRow(
            row,
            lines: byReturn[row['id']] ?? const <ReturnLineRecord>[],
          ),
        )
        .toList();
  }

  /// Every saved return, newest first (used by the reports and the exports).
  Future<List<ReturnRecord>> getAll() async {
    final rows = await _database.db.query(
      DbTables.returns,
      orderBy: 'id DESC',
    );
    return rows.map(ReturnRecord.fromRow).toList();
  }

  /// How much was credited on [invoiceId] so far (at the sale prices).
  Future<Money> creditedForInvoice(int invoiceId) =>
      _sumOf(_database.db, 'total_cents', invoiceId);

  /// How much cash was already handed back on [invoiceId].
  Future<Money> refundedForInvoice(int invoiceId) =>
      _sumOf(_database.db, 'refund_cents', invoiceId);

  /// Saves [draft]: the pieces go back to the stock and the credit is recorded
  /// in one transaction.
  ///
  /// The prices and the cost always come from the invoice lines, and the cash
  /// handed back can never exceed what the customer actually paid on that
  /// invoice - so neither the credit nor the refund can be invented by a stale
  /// screen.
  Future<int> create(ReturnDraft draft) async {
    draft.validate();
    final now = _clock();
    final returnDate = AppDates.isoDate(now);
    final createdAt = AppDates.isoDateTime(now);

    final returnId = await _database.db.transaction((txn) async {
      final headers = await txn.query(
        DbTables.invoices,
        columns: <String>[
          'id',
          'customer_id',
          'customer_name',
          'invoice_date',
          'total_cents',
          'paid_cents',
        ],
        where: 'id = ?',
        whereArgs: <Object?>[draft.invoiceId],
        limit: 1,
      );
      if (headers.isEmpty) throw const NotFoundException('الفاتورة غير موجودة.');
      final header = headers.first;

      final available = <int, ReturnableLine>{
        for (final entry in (await _returnableRows(txn, draft.invoiceId)).map(
          (row) => ReturnableLine(
            invoiceItemId: row.readInt('id'),
            line: InvoiceLineRecord.fromRow(row),
            returned: row.readInt('returned'),
          ),
        ))
          entry.invoiceItemId: entry,
      };

      final chosen = <({ReturnableLine entry, int quantity})>[];
      for (final line in draft.selected) {
        final entry = available[line.invoiceItemId];
        if (entry == null) {
          throw const ValidationException(
            'أحد أسطر الفاتورة لم يعد موجوداً، أعد تحميل الفاتورة.',
          );
        }
        if (line.quantity > entry.remaining) {
          throw ValidationException(
            'الكمية المرتجعة من "${entry.line.itemName}" أكبر من المتبقي '
            '(${entry.remaining}).',
          );
        }
        chosen.add((entry: entry, quantity: line.quantity));
      }

      final credit = Money.sum(
        chosen.map((item) => item.entry.line.unitPrice * item.quantity),
      );
      final cost = Money.sum(
        chosen.map((item) => item.entry.line.unitCost * item.quantity),
      );
      final alreadyRefunded = await _sumOf(
        txn,
        'refund_cents',
        draft.invoiceId,
      );
      final paid = Money(header.readInt('paid_cents'));
      final refundable = paid - alreadyRefunded;
      if (draft.refund > credit || draft.refund > refundable) {
        throw ValidationException(
          'المبلغ المعاد للزبون أكبر من المسموح '
          '(${(refundable < credit ? refundable : credit).format()}).',
        );
      }

      final id = await txn.insert(DbTables.returns, <String, Object?>{
        'invoice_id': draft.invoiceId,
        'customer_id': header['customer_id'],
        'customer_name': header.readString('customer_name'),
        'return_date': returnDate,
        'created_at': createdAt,
        'total_cents': credit.cents,
        'cost_cents': cost.cents,
        'refund_cents': draft.refund.cents,
        'notes': draft.notes.trim(),
      });

      final batch = txn.batch();
      for (final item in chosen) {
        final entry = item.entry;
        batch.insert(DbTables.returnItems, <String, Object?>{
          'return_id': id,
          'invoice_item_id': entry.invoiceItemId,
          'item_id': entry.line.itemId,
          'item_name': entry.line.itemName,
          'category': entry.line.category,
          'sku': entry.line.sku,
          'container': entry.line.container,
          'unit': entry.line.unit,
          'quantity': item.quantity,
          'unit_cost_cents': entry.line.unitCost.cents,
          'unit_price_cents': entry.line.unitPrice.cents,
        });
        final itemId = entry.line.itemId;
        if (itemId != null) {
          // A line whose product was deleted still gets its credit; only the
          // stock of a product that still exists can grow.
          batch.rawUpdate(
            'UPDATE ${DbTables.items} SET quantity = quantity + ? WHERE id = ?',
            <Object?>[item.quantity, itemId],
          );
        }
      }
      await batch.commit(noResult: true);
      return id;
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.returnCreated, invoiceId: draft.invoiceId);
    return returnId;
  }

  /// Deletes the return [id]: its pieces leave the stock again and its credit
  /// disappears from the invoice and from the customer's balance.
  ///
  /// Refused when some of those pieces were sold in the meantime, because
  /// taking them back would drive the stock below zero, and when a later payout
  /// settled part of its credit, because the payout would be left without the
  /// record it settled.
  Future<void> delete(int id) async {
    final invoiceId = await _database.db.transaction((txn) async {
      final headers = await txn.query(
        DbTables.returns,
        columns: <String>['invoice_id', 'settled_at'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (headers.isEmpty) throw const NotFoundException('المرتجع غير موجود.');
      if (headers.first.readString('settled_at').isNotEmpty) {
        throw const ConflictException(
          'لا يمكن حذف مرتجع سُوِّي رصيده لاحقاً عبر سند صرف، لأن حذفه يُلغي '
          'أثر التسوية ويُبقي السند بلا مرجع. اترك المرتجع في السجل، وصحّح '
          'بعملية جديدة إن لزم.',
        );
      }
      final invoiceId = headers.first.readInt('invoice_id');

      final lines = await txn.query(
        DbTables.returnItems,
        columns: <String>['item_id', 'quantity', 'item_name'],
        where: 'return_id = ?',
        whereArgs: <Object?>[id],
      );
      for (final line in lines) {
        final itemId = line['item_id'] as int?;
        if (itemId == null) continue;
        final quantity = line.readInt('quantity');
        final changed = await txn.rawUpdate(
          'UPDATE ${DbTables.items} SET quantity = quantity - ? '
          'WHERE id = ? AND quantity >= ?',
          <Object?>[quantity, itemId, quantity],
        );
        if (changed == 0) {
          throw ValidationException(
            'لا يمكن حذف هذا المرتجع: كميات "${line.readString('item_name')}" '
            'لم تعد كلها في المخزون لأن بعضها بيع بعد الإرجاع.',
          );
        }
      }
      await txn.delete(
        DbTables.returns,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return invoiceId;
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.returnDeleted, invoiceId: invoiceId);
  }

  /// The lines of [invoiceId] with their returned quantity, inside [db] so a
  /// transaction sees the stock of returns made a moment earlier.
  static Future<List<Map<String, Object?>>> _returnableRows(
    DatabaseExecutor db,
    int invoiceId,
  ) => db.rawQuery(
    'SELECT l.*, IFNULL((SELECT SUM(ri.quantity) '
    'FROM ${DbTables.returnItems} ri WHERE ri.invoice_item_id = l.id), 0) '
    'AS returned '
    'FROM ${DbTables.invoiceItems} l WHERE l.invoice_id = ? ORDER BY l.id',
    <Object?>[invoiceId],
  );

  static Future<Money> _sumOf(
    DatabaseExecutor db,
    String column,
    int invoiceId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT IFNULL(SUM($column), 0) AS total FROM ${DbTables.returns} '
      'WHERE invoice_id = ?',
      <Object?>[invoiceId],
    );
    return Money(rows.first.readInt('total'));
  }
}
