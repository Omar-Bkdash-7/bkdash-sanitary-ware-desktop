import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_balance_query.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_draft.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_line_export.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_payment_allocator.dart';
import 'package:sqflite/sqflite.dart';

/// Buys pieces from customers into the stock and records what is owed to them.
class PurchaseRepository {
  PurchaseRepository(this._database, this._changes, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Clock _clock;

  /// Saves [draft] as a new purchase and returns its number.
  ///
  /// Everything happens in one transaction: the stock grows, the item costs are
  /// updated (weighted average), the purchase and its lines are written and the
  /// payment made now is recorded - or nothing changes at all.
  Future<int> create(PurchaseDraft draft) async {
    draft.validate();
    final now = _clock();
    final createdAt = AppDates.isoDateTime(now);
    final date = AppDates.isoDate(now);
    final total = draft.total;
    final paid = draft.paidNow;
    final customer = draft.customer;

    final purchaseId = await _database.db.transaction((txn) async {
      final prepared = <_PreparedPurchaseLine>[];
      for (final line in draft.lines) {
        final itemId = line.itemId;
        if (itemId != null) {
          prepared.add(await _addToExistingItem(txn, line, itemId));
        } else {
          prepared.add(await _createItem(txn, line, createdAt));
        }
      }

      final id = await txn.insert(DbTables.purchases, <String, Object?>{
        'customer_id': customer.id,
        'customer_name': customer.name,
        'customer_phone': customer.phone,
        'purchase_date': date,
        'created_at': createdAt,
        'total_cents': total.cents,
        'paid_cents': paid.cents,
        'notes': draft.notes.trim(),
      });

      final batch = txn.batch();
      for (final line in prepared) {
        batch.insert(DbTables.purchaseItems, <String, Object?>{
          'purchase_id': id,
          'item_id': line.itemId,
          'item_name': line.itemName,
          'category': line.category,
          'sku': line.sku,
          'container': line.container,
          'unit': line.unit,
          'quantity': line.quantity,
          'unit_cost_cents': line.unitCost.cents,
          'previous_quantity': line.previousQuantity,
          'previous_cost_cents': line.previousCost.cents,
        });
      }
      await batch.commit(noResult: true);

      if (paid.isPositive) {
        await txn.insert(DbTables.purchasePayments, <String, Object?>{
          'purchase_id': id,
          'amount_cents': paid.cents,
          'paid_at': createdAt,
          'paid_date': date,
        });
      }
      return id;
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.purchase);
    return purchaseId;
  }

  /// Adds the pieces of [line] to an item that is already in the stock.
  ///
  /// The cost becomes the weighted average of the old stock and the new pieces,
  /// so the inventory value follows what the shop actually paid.
  Future<_PreparedPurchaseLine> _addToExistingItem(
    DatabaseExecutor txn,
    PurchaseLine line,
    int itemId,
  ) async {
    final rows = await txn.query(
      DbTables.items,
      columns: <String>[
        'category',
        'name',
        'sku',
        'container',
        'unit',
        'quantity',
        'cost_cents',
      ],
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw NotFoundException('الصنف "${line.itemName}" لم يعد موجوداً.');
    }
    final row = rows.first;
    final oldQuantity = row['quantity']! as int;
    final oldCost = row['cost_cents']! as int;
    final newQuantity = oldQuantity + line.quantity;
    final newCost = _weightedCost(
      oldQuantity: oldQuantity,
      oldCost: oldCost,
      boughtQuantity: line.quantity,
      boughtCost: line.unitCost.cents,
      newQuantity: newQuantity,
    );

    await txn.update(
      DbTables.items,
      <String, Object?>{'quantity': newQuantity, 'cost_cents': newCost},
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );

    return _PreparedPurchaseLine(
      itemId: itemId,
      itemName: row['name']! as String,
      category: row['category']! as String,
      sku: row['sku']! as String,
      container: (row['container'] as int?) ?? 0,
      unit: row['unit']! as String,
      quantity: line.quantity,
      unitCost: line.unitCost,
      previousQuantity: oldQuantity,
      previousCost: Money(oldCost),
    );
  }

  /// Creates the inventory item for a line that is not in the stock yet.
  Future<_PreparedPurchaseLine> _createItem(
    DatabaseExecutor txn,
    PurchaseLine line,
    String createdAt,
  ) async {
    final name = line.itemName.trim();
    final category = line.category.trim();
    final unit = line.unit.trim().isEmpty ? AppStrings.piece : line.unit.trim();
    final sku = line.sku.trim().isEmpty
        ? await _generateSku(txn)
        : line.sku.trim();
    try {
      final itemId = await txn.insert(DbTables.items, <String, Object?>{
        'category': category,
        'name': name,
        'sku': sku,
        'container': line.container,
        'unit': unit,
        'cost_cents': line.unitCost.cents,
        'price_cents': line.salePrice.cents,
        'quantity': line.quantity,
        'notes': '',
        'created_at': createdAt,
      });
      return _PreparedPurchaseLine(
        itemId: itemId,
        itemName: name,
        category: category,
        sku: sku,
        container: line.container,
        unit: unit,
        quantity: line.quantity,
        unitCost: line.unitCost,
        previousQuantity: 0,
        // Keeping the purchase cost means a deleted purchase leaves a sensible
        // (zero-stock) item behind instead of a zero-cost one.
        previousCost: line.unitCost,
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw DuplicateSkuException(sku, container: line.container);
      }
      rethrow;
    }
  }

  /// Deletes a purchase that is still the last movement on its items.
  ///
  /// The stock goes back to what it was and the payment made at the purchase is
  /// removed. A purchase whose pieces were already sold, or whose items changed
  /// afterwards, is kept: reversing it would corrupt the inventory value. A
  /// purchase that later payouts were allocated to is kept for the same reason.
  Future<void> delete(int id) async {
    await _database.db.transaction((txn) async {
      final headers = await txn.query(
        DbTables.purchases,
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (headers.isEmpty) {
        throw const NotFoundException('عملية الشراء غير موجودة.');
      }

      final laterPayments = await txn.query(
        DbTables.purchasePayments,
        columns: <String>['id'],
        where: 'purchase_id = ? AND payout_id IS NOT NULL',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (laterPayments.isNotEmpty) {
        throw const ConflictException(
          'لا يمكن حذف عملية شراء سُدِّد جزء منها لاحقاً، لأن المبلغ '
          'مسجّل في حساب الزبون.',
        );
      }

      final lines = await txn.query(
        DbTables.purchaseItems,
        where: 'purchase_id = ?',
        whereArgs: <Object?>[id],
      );
      for (final line in lines) {
        final itemId = line['item_id'] as int?;
        if (itemId == null) continue;

        // A later purchase of the same item can bring the quantity and the cost
        // back to the numbers this purchase left behind (buy, sell, buy again).
        // Reversing this purchase then would silently remove the newer pieces,
        // so only the newest purchase of an item may be deleted first.
        final laterPurchase = await txn.rawQuery(
          'SELECT 1 FROM ${DbTables.purchaseItems} '
          'WHERE item_id = ? AND purchase_id > ? LIMIT 1',
          <Object?>[itemId, id],
        );
        if (laterPurchase.isNotEmpty) {
          throw ConflictException(
            'لا يمكن حذف عملية الشراء لأن الصنف "${line['item_name']}" '
            'اشتريناه لاحقاً في عملية أخرى. احذف العملية الأحدث أولاً.',
          );
        }

        final items = await txn.query(
          DbTables.items,
          columns: <String>['name', 'quantity', 'cost_cents'],
          where: 'id = ?',
          whereArgs: <Object?>[itemId],
          limit: 1,
        );
        if (items.isEmpty) continue;

        final item = items.first;
        final boughtQuantity = line['quantity']! as int;
        final previousQuantity = line['previous_quantity']! as int;
        final previousCost = line['previous_cost_cents']! as int;
        final expectedQuantity = previousQuantity + boughtQuantity;
        final expectedCost = _weightedCost(
          oldQuantity: previousQuantity,
          oldCost: previousCost,
          boughtQuantity: boughtQuantity,
          boughtCost: line['unit_cost_cents']! as int,
          newQuantity: expectedQuantity,
        );
        final currentQuantity = item['quantity']! as int;
        final currentCost = item['cost_cents']! as int;
        if (currentQuantity != expectedQuantity ||
            currentCost != expectedCost) {
          throw ConflictException(
            'لا يمكن حذف عملية الشراء لأن مخزون الصنف '
            '"${item['name']}" أو تكلفته تغيّرا بعدها. '
            'اترك العملية في السجل حفاظاً على دقة الحسابات.',
          );
        }

        await txn.update(
          DbTables.items,
          <String, Object?>{
            'quantity': previousQuantity,
            'cost_cents': previousCost,
          },
          where: 'id = ?',
          whereArgs: <Object?>[itemId],
        );
      }

      await txn.delete(
        DbTables.purchasePayments,
        where: 'purchase_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        DbTables.purchaseItems,
        where: 'purchase_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        DbTables.purchases,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.purchaseDeleted);
  }

  /// Purchases, newest first. [fromDate] / [toDate] are "yyyy-MM-dd" inclusive.
  Future<List<Purchase>> getPurchases({
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
      conditions.add('purchase_date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      conditions.add('purchase_date <= ?');
      args.add(toDate);
    }
    final rows = await _database.db.query(
      DbTables.purchases,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
    );
    return rows.map(Purchase.fromRow).toList();
  }

  Future<PurchaseDetails?> getDetails(int id) async {
    final db = _database.db;
    final headers = await db.query(
      DbTables.purchases,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (headers.isEmpty) return null;
    final lines = await db.query(
      DbTables.purchaseItems,
      where: 'purchase_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id',
    );
    final payments = await db.query(
      DbTables.purchasePayments,
      where: 'purchase_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id',
    );
    return PurchaseDetails(
      purchase: Purchase.fromRow(headers.first),
      lines: lines.map(PurchaseLineRecord.fromRow).toList(),
      payments: payments.map(PurchasePaymentRecord.fromRow).toList(),
    );
  }

  /// Every product line of every purchase (used by the CSV export).
  Future<List<PurchaseLineExport>> getAllLines() async {
    final rows = await _database.db.rawQuery(
      'SELECT l.*, p.purchase_date, p.customer_name '
      'FROM ${DbTables.purchaseItems} l '
      'JOIN ${DbTables.purchases} p ON p.id = l.purchase_id '
      'ORDER BY l.purchase_id, l.id',
    );
    return rows
        .map(
          (row) => PurchaseLineExport(
            purchaseId: row['purchase_id']! as int,
            purchaseDate: row['purchase_date']! as String,
            customerName: row['customer_name']! as String,
            line: PurchaseLineRecord.fromRow(row),
          ),
        )
        .toList();
  }

  /// Pays [amount] to [customerId]: oldest unpaid purchases first, then the
  /// credit of his returns that was never handed back in cash.
  ///
  /// Only the net payable can be paid: when the customer still owes more than
  /// the shop owes him, the settlement goes the other way (a receipt).
  ///
  /// The part that no purchase covers is the credit of an old return (the shop
  /// kept it then). It is paid by adding it to that return's cash, so the
  /// balance drops by exactly what left the shop and no money is left hanging.
  Future<void> payCustomer({
    required int customerId,
    required Money amount,
    String note = '',
  }) async {
    if (!amount.isPositive) {
      throw const ValidationException('المبلغ يجب أن يكون أكبر من صفر.');
    }
    final now = _clock();
    final paidAt = AppDates.isoDateTime(now);
    final paidDate = AppDates.isoDate(now);

    await _database.db.transaction((txn) async {
      final net = await CustomerBalanceQuery.net(txn, customerId);
      if (net.isPositive) {
        throw const ValidationException(
          'الزبون مدين للشركة. سجّل تسديداً منه بدلاً من الدفع له.',
        );
      }
      if (net.isZero) {
        throw const ValidationException('لا توجد مبالغ مستحقة لهذا الزبون.');
      }
      final payable = -net;
      if (amount > payable) {
        throw ValidationException(
          'المبلغ أكبر من صافي المستحق للزبون (${payable.format()}).',
        );
      }

      final rows = await txn.rawQuery(
        'SELECT id, total_cents - paid_cents AS remaining_cents '
        'FROM ${DbTables.purchases} '
        'WHERE customer_id = ? AND total_cents > paid_cents '
        'ORDER BY purchase_date, id',
        <Object?>[customerId],
      );
      final outstanding = rows
          .map(
            (row) => OutstandingPurchase(
              purchaseId: row.readInt('id'),
              remaining: Money(row.readInt('remaining_cents')),
            ),
          )
          .toList();
      // A negative balance can come from a return credit alone: there is then
      // nothing to allocate to a purchase, and the credit is settled below.
      final allocations = outstanding.isEmpty
          ? const <PurchasePaymentAllocation>[]
          : PurchasePaymentAllocator.allocate(outstanding, amount);

      final payoutId = await txn
          .insert(DbTables.customerPayouts, <String, Object?>{
            'customer_id': customerId,
            'amount_cents': amount.cents,
            'note': note.trim(),
            'paid_at': paidAt,
            'paid_date': paidDate,
          });
      var left = amount.cents;
      for (final allocation in allocations) {
        await txn.insert(DbTables.purchasePayments, <String, Object?>{
          'purchase_id': allocation.purchaseId,
          'payout_id': payoutId,
          'amount_cents': allocation.amount.cents,
          'paid_at': paidAt,
          'paid_date': paidDate,
        });
        await txn.rawUpdate(
          'UPDATE ${DbTables.purchases} SET paid_cents = paid_cents + ? '
          'WHERE id = ?',
          <Object?>[allocation.amount.cents, allocation.purchaseId],
        );
        left -= allocation.amount.cents;
      }

      // Whatever the purchases could not take is the credit still standing on
      // the customer's returns: handing it over now is the cash of those
      // returns, so it is added to their refund instead of being forgotten.
      if (left > 0) {
        final credits = await txn.rawQuery(
          'SELECT id, total_cents - refund_cents AS credit_cents '
          'FROM ${DbTables.returns} '
          'WHERE customer_id = ? AND total_cents > refund_cents '
          'ORDER BY return_date, id',
          <Object?>[customerId],
        );
        for (final row in credits) {
          if (left == 0) break;
          final credit = row.readInt('credit_cents');
          final portion = credit < left ? credit : left;
          await txn.rawUpdate(
            'UPDATE ${DbTables.returns} SET refund_cents = refund_cents + ?, '
            'settled_at = CASE WHEN settled_at = \'\' THEN ? ELSE settled_at END '
            'WHERE id = ?',
            <Object?>[portion, paidAt, row.readInt('id')],
          );
          left -= portion;
        }
      }
      if (left > 0) {
        throw const ValidationException(
          'تعذّر توزيع المبلغ على مستحقات الزبون. أعد تحميل حسابه وحاول '
          'مرة أخرى.',
        );
      }
    });

    _changes.markChanged();
    _changes.reportWrite(DataWrite.payout);
  }

  /// Payouts made to [customerId], newest first.
  Future<List<CustomerPayout>> payoutsFor(int customerId) async {
    final rows = await _database.db.query(
      DbTables.customerPayouts,
      where: 'customer_id = ?',
      whereArgs: <Object?>[customerId],
      orderBy: 'id DESC',
    );
    return rows.map(CustomerPayout.fromRow).toList();
  }

  /// Rounded weighted average of the old stock and the purchased pieces.
  static int _weightedCost({
    required int oldQuantity,
    required int oldCost,
    required int boughtQuantity,
    required int boughtCost,
    required int newQuantity,
  }) {
    final total = oldQuantity * oldCost + boughtQuantity * boughtCost;
    return (total + newQuantity ~/ 2) ~/ newQuantity;
  }

  Future<String> _generateSku(DatabaseExecutor txn) async {
    final next =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT IFNULL(MAX(id), 0) + 1 FROM ${DbTables.items}',
          ),
        ) ??
        1;
    var number = next;
    while (true) {
      final candidate = 'ITM-${number.toString().padLeft(4, '0')}';
      final taken = await txn.query(
        DbTables.items,
        columns: <String>['id'],
        where: 'sku = ?',
        whereArgs: <Object?>[candidate],
        limit: 1,
      );
      if (taken.isEmpty) return candidate;
      number++;
    }
  }
}

/// A line after the stock was prepared, ready to be written.
final class _PreparedPurchaseLine {
  const _PreparedPurchaseLine({
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.sku,
    required this.container,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.previousQuantity,
    required this.previousCost,
  });

  final int itemId;
  final String itemName;
  final String category;
  final String sku;
  final int container;
  final String unit;
  final int quantity;
  final Money unitCost;
  final int previousQuantity;
  final Money previousCost;
}
