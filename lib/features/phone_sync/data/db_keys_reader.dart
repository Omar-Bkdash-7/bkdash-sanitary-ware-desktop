import 'dart:io';

import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/row_reader.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/db_key_sets.dart';
import 'package:sqflite/sqflite.dart';

/// Reads the identity and the signature of every record of a database (see
/// [DbKeySets]). Only a handful of narrow columns are read, so even a database
/// with years of invoices answers in a fraction of a second.
abstract final class DbKeysReader {
  /// Reads an open database (the live one).
  static Future<DbKeySets> read(DatabaseExecutor db) async {
    final invoices = await db.rawQuery(
      'SELECT id, created_at, customer_name, payment_method, total_cents, '
      'paid_cents FROM ${DbTables.invoices}',
    );
    final customers = await db.rawQuery(
      'SELECT id, created_at, name, phone, address '
      'FROM ${DbTables.customers}',
    );
    final items = await db.rawQuery(
      'SELECT id, sku, name, category, cost_cents, price_cents, quantity '
      'FROM ${DbTables.items}',
    );
    final receipts = await db.rawQuery(
      'SELECT id, customer_id, paid_at, amount_cents, note '
      'FROM ${DbTables.customerReceipts}',
    );
    final newestInvoice = await db.rawQuery(
      'SELECT MAX(created_at) AS newest FROM ${DbTables.invoices}',
    );
    final newestReceipt = await db.rawQuery(
      'SELECT MAX(paid_at) AS newest FROM ${DbTables.customerReceipts}',
    );

    final newest = <String>[
      (newestInvoice.first['newest'] as String?) ?? '',
      (newestReceipt.first['newest'] as String?) ?? '',
    ]..sort();

    return DbKeySets(
      invoices: <String, String>{
        for (final row in invoices)
          '${row.readInt('id')}|${row.readString('created_at')}':
              '${row.readString('customer_name')}|'
              '${row.readString('payment_method')}|'
              '${row.readInt('total_cents')}|${row.readInt('paid_cents')}',
      },
      customers: <String, String>{
        for (final row in customers)
          '${row.readInt('id')}|${row.readString('created_at')}':
              '${row.readString('name')}|${row.readString('phone')}|'
              '${row.readString('address')}',
      },
      // The catalogue every database starts with has the same ids and SKUs on
      // both devices but different creation times, so an item is identified by
      // id and SKU alone.
      items: <String, String>{
        for (final row in items)
          '${row.readInt('id')}|${row.readString('sku')}':
              '${row.readString('name')}|${row.readString('category')}|'
              '${row.readInt('cost_cents')}|${row.readInt('price_cents')}|'
              '${row.readInt('quantity')}',
      },
      receipts: <String, String>{
        for (final row in receipts)
          '${row.readInt('id')}|${row.readInt('customer_id')}|'
                  '${row.readString('paid_at')}':
              '${row.readInt('amount_cents')}|${row.readString('note')}',
      },
      lastActivity: newest.last,
    );
  }

  /// Reads a database file without changing it.
  static Future<DbKeySets> readFile(
    File file, {
    required DatabaseFactory factory,
  }) async {
    Database? candidate;
    try {
      candidate = await factory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      return await read(candidate);
    } on DatabaseException {
      throw const BackupException('تعذّرت قراءة محتوى النسخة الاحتياطية.');
    } finally {
      await candidate?.close();
    }
  }
}
