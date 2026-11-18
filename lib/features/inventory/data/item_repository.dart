import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:sqflite/sqflite.dart';

/// Reads and writes the products of the shop.
class ItemRepository {
  ItemRepository(this._database, this._changes, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DataChangeNotifier _changes;
  final Clock _clock;

  Future<List<Item>> getAll() async {
    final rows = await _database.db.query(
      DbTables.items,
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(Item.fromRow).toList();
  }

  Future<Item?> findById(int id) async {
    final rows = await _database.db.query(
      DbTables.items,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Item.fromRow(rows.first);
  }

  Future<Item> create(ItemInput input) async {
    input.validate();
    final db = _database.db;
    final sku = input.sku.trim().isEmpty
        ? await _generateSku(db)
        : input.sku.trim();
    try {
      final id = await db.insert(DbTables.items, <String, Object?>{
        ..._toRow(input),
        'sku': sku,
        'created_at': AppDates.isoDateTime(_clock()),
      });
      _changes.markChanged();
      _changes.reportWrite(DataWrite.inventory);
      return (await findById(id))!;
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) throw DuplicateSkuException(sku);
      rethrow;
    }
  }

  Future<Item> update(int id, ItemInput input) async {
    input.validate();
    final values = _toRow(input);
    if (input.sku.trim().isNotEmpty) values['sku'] = input.sku.trim();
    try {
      final changed = await _database.db.update(
        DbTables.items,
        values,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (changed == 0) throw const NotFoundException('الصنف غير موجود.');
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw DuplicateSkuException(input.sku.trim());
      }
      rethrow;
    }
    _changes.markChanged();
    _changes.reportWrite(DataWrite.inventory);
    return (await findById(id))!;
  }

  /// Deleting an item keeps the old invoices intact (they hold their own copy
  /// of the item name, price and cost).
  Future<void> delete(int id) async {
    await _database.db.delete(
      DbTables.items,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    _changes.markChanged();
    _changes.reportWrite(DataWrite.inventory);
  }

  Map<String, Object?> _toRow(ItemInput input) => <String, Object?>{
    'category': input.category.trim(),
    'name': input.name.trim(),
    'unit': input.unit.trim().isEmpty ? AppStrings.piece : input.unit.trim(),
    'cost_cents': input.cost.cents,
    'price_cents': input.price.cents,
    'quantity': input.quantity,
    'notes': input.notes.trim(),
  };

  Future<String> _generateSku(Database db) async {
    final next =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT IFNULL(MAX(id), 0) + 1 FROM ${DbTables.items}',
          ),
        ) ??
        1;
    var number = next;
    while (true) {
      final candidate = 'ITM-${number.toString().padLeft(4, '0')}';
      final taken = await db.query(
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
