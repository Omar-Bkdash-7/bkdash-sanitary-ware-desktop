import 'dart:io';

import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/database/app_database.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final DatabaseFactory factory = databaseFactoryFfi;

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bkdash_upgrade_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('a version 1 database keeps its data and gains purchases', () async {
    final path = p.join(root.path, AppConstants.databaseFileName);
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          final batch = db.batch();
          // The purchase statements are the tail of the current schema.
          final version1 = DbSchema.createStatements.take(
            DbSchema.createStatements.length - DbSchema.upgradeTo2.length,
          );
          for (final statement in version1) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
      ),
    );
    await legacy.insert('customers', <String, Object?>{
      'name': 'سامر',
      'phone': '0999',
      'address': '',
      'notes': '',
      'created_at': '2026-11-09T09:00:00',
    });
    await legacy.insert('items', <String, Object?>{
      'category': 'أنابيب',
      'name': 'أنبوب',
      'sku': 'PIP-1',
      'unit': 'متر',
      'cost_cents': 1000,
      'price_cents': 1500,
      'quantity': 10,
      'notes': '',
      'created_at': '2026-11-09T09:00:00',
    });
    await legacy.close();

    final upgraded = await AppDatabase.open(
      factory: factory,
      directory: root.path,
      seed: false,
    );
    addTearDown(upgraded.close);

    expect(await upgraded.schemaVersion(), 2);
    final tables = (await upgraded.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).toSet();
    expect(tables, containsAll(DbTables.all));
    expect((await upgraded.db.query('customers')).single['name'], 'سامر');
    expect((await upgraded.db.query('items')).single['name'], 'أنبوب');

    final customerId =
        (await upgraded.db.query('customers')).single['id']! as int;
    final purchaseId = await upgraded.db.insert('purchases', <String, Object?>{
      'customer_id': customerId,
      'customer_name': 'سامر',
      'customer_phone': '0999',
      'purchase_date': '2026-11-10',
      'created_at': '2026-11-10T10:00:00',
      'total_cents': 4000,
      'paid_cents': 0,
      'notes': '',
    });
    expect(purchaseId, 1);
    final summary = await upgraded.summarize();
    expect(summary.purchases, 1);
  });
}
