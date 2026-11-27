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

  /// Creates a version 1 file (the schema before purchases and containers).
  Future<int> legacyDatabase(String path) async {
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          final batch = db.batch();
          // Version 1 ends where the purchase tables start.
          final purchaseStart = DbSchema.createStatements.indexWhere(
            (statement) =>
                statement.contains('CREATE TABLE ${DbTables.purchases}'),
          );
          final version1 = DbSchema.createStatements.take(purchaseStart);
          for (final statement in version1) {
            // The current statements know containers; version 1 did not.
            if (statement.contains('idx_items_sku_container') ||
                statement.contains('idx_items_container')) {
              continue;
            }
            var sql = statement.replaceFirst(
              '  container INTEGER NOT NULL DEFAULT 0 CHECK (container >= 0),\n',
              '',
            );
            if (sql.contains('CREATE TABLE items (')) {
              sql = sql.replaceFirst(
                '  sku TEXT NOT NULL,',
                '  sku TEXT NOT NULL UNIQUE,',
              );
            }
            batch.execute(sql);
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
    final itemId = await legacy.insert('items', <String, Object?>{
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
    final invoiceId = await legacy.insert('invoices', <String, Object?>{
      'customer_id': null,
      'customer_name': 'زبون نقدي',
      'customer_phone': '',
      'payment_method': 'cash',
      'invoice_date': '2026-11-09',
      'created_at': '2026-11-09T09:05:00',
      'total_cents': 3000,
      'paid_cents': 3000,
      'profit_cents': 1000,
      'notes': '',
    });
    await legacy.insert('invoice_items', <String, Object?>{
      'invoice_id': invoiceId,
      'item_id': itemId,
      'item_name': 'أنبوب',
      'category': 'أنابيب',
      'sku': 'PIP-1',
      'unit': 'متر',
      'quantity': 2,
      'unit_cost_cents': 1000,
      'unit_price_cents': 1500,
    });
    await legacy.close();
    return itemId;
  }

  test('a version 1 database keeps its data, gains purchases and containers',
      () async {
    final path = p.join(root.path, AppConstants.databaseFileName);
    final itemId = await legacyDatabase(path);

    final upgraded = await AppDatabase.open(
      factory: factory,
      directory: root.path,
      seed: false,
    );
    addTearDown(upgraded.close);

    expect(await upgraded.schemaVersion(), 5);
    final tables = (await upgraded.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).toSet();
    expect(tables, containsAll(DbTables.all));
    expect((await upgraded.db.query('customers')).single['name'], 'سامر');

    final item = (await upgraded.db.query('items')).single;
    expect(item['name'], 'أنبوب');
    expect(item['container'], 0);
    expect(item['id'], itemId);

    // The rebuild of `items` must not lose the line links.
    final line = (await upgraded.db.query('invoice_items')).single;
    expect(line['item_id'], itemId);
    expect(line['container'], 0);

    final indexes = (await upgraded.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    )).map((row) => row['name']).toSet();
    expect(indexes, contains('idx_items_sku_container'));

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
    expect((await upgraded.summarize()).purchases, 1);
  });

  test('a version 4 database gains the settlement marker of returns',
      () async {
    final path = p.join(root.path, AppConstants.databaseFileName);
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final statement in DbSchema.createStatements) {
            // The returns table the way version 4 created it.
            batch.execute(
              statement.replaceFirst(
                "  settled_at TEXT NOT NULL DEFAULT '',\n",
                '',
              ),
            );
          }
          await batch.commit(noResult: true);
        },
      ),
    );
    final invoiceId = await legacy.insert('invoices', <String, Object?>{
      'customer_id': null,
      'customer_name': 'زبون نقدي',
      'customer_phone': '',
      'payment_method': 'cash',
      'invoice_date': '2026-11-20',
      'created_at': '2026-11-20T09:00:00',
      'total_cents': 2000,
      'paid_cents': 2000,
      'profit_cents': 500,
      'notes': '',
    });
    final returnId = await legacy.insert('returns', <String, Object?>{
      'invoice_id': invoiceId,
      'customer_id': null,
      'customer_name': 'زبون نقدي',
      'return_date': '2026-11-20',
      'created_at': '2026-11-20T10:00:00',
      'total_cents': 1000,
      'cost_cents': 600,
      'refund_cents': 400,
      'notes': '',
    });
    await legacy.close();

    final upgraded = await AppDatabase.open(
      factory: factory,
      directory: root.path,
      seed: false,
    );
    addTearDown(upgraded.close);

    expect(await upgraded.schemaVersion(), 5);
    final columns = (await upgraded.db.rawQuery('PRAGMA table_info(returns)'))
        .map((row) => row['name'])
        .toSet();
    expect(columns, contains('settled_at'));
    // The old return keeps its credit untouched.
    final saved = (await upgraded.db.query('returns')).single;
    expect(saved['id'], returnId);
    expect(saved['refund_cents'], 400);
    expect(saved['settled_at'], '');
  });

  test('the same SKU is allowed once per container', () async {
    final path = p.join(root.path, AppConstants.databaseFileName);
    await legacyDatabase(path);

    final upgraded = await AppDatabase.open(
      factory: factory,
      directory: root.path,
      seed: false,
    );
    addTearDown(upgraded.close);

    Future<int> addItem(String sku, int container) => upgraded.db.insert(
      'items',
      <String, Object?>{
        'category': 'أنابيب',
        'name': 'أنبوب',
        'sku': sku,
        'container': container,
        'unit': 'متر',
        'cost_cents': 1200,
        'price_cents': 1800,
        'quantity': 5,
        'notes': '',
        'created_at': '2026-11-11T09:00:00',
      },
    );

    // Container 2 may hold the same SKU with its own cost.
    await addItem('PIP-1', 2);
    // A second copy inside container 2 is refused.
    await expectLater(addItem('PIP-1', 2), throwsA(isA<DatabaseException>()));
    // Items that are not from a container share container 0.
    await addItem('PIP-2', 0);
    await expectLater(addItem('PIP-2', 0), throwsA(isA<DatabaseException>()));

    final rows = await upgraded.db.query(
      'items',
      orderBy: 'container',
    );
    expect(rows.map((row) => '${row['sku']}|${row['container']}'),
        <String>['PIP-1|0', 'PIP-2|0', 'PIP-1|2']);
  });
}
