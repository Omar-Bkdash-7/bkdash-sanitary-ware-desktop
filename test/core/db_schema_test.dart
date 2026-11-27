import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every table is created and the purchase tables are part of version 2',
    () {
      final schema = DbSchema.createStatements.join('\n');
      expect(schema, contains('container INTEGER NOT NULL DEFAULT 0'));
      expect(
        schema,
        contains('CREATE UNIQUE INDEX idx_items_sku_container'),
      );

      for (final table in DbTables.all) {
        expect(
          schema,
          contains('CREATE TABLE $table'),
          reason: '$table is missing from the create statements',
        );
      }

      for (final table in const [
        DbTables.purchases,
        DbTables.purchaseItems,
        DbTables.customerPayouts,
        DbTables.purchasePayments,
      ]) {
        expect(
          DbSchema.upgradeTo2.join('\n'),
          contains('CREATE TABLE $table'),
          reason: '$table is not added by the version 2 migration',
        );
      }
    },
  );

  test('the container migration rebuilds items and keeps the links', () {
    final upgrade = DbSchema.upgradeTo3.join('\n');
    expect(upgrade, contains('CREATE TEMP TABLE _item_links'));
    expect(upgrade, contains('DROP TABLE items'));
    expect(upgrade, contains('ALTER TABLE items_new RENAME TO items'));
    expect(upgrade, contains('idx_items_sku_container'));
    expect(upgrade, contains('UPDATE invoice_items SET item_id'));
    expect(upgrade, contains('UPDATE purchase_items SET item_id'));
  });

  test('an older backup stays valid after returns were added', () {
    expect(DbTables.requiredForVersion(1), DbTables.version1);
    expect(DbTables.requiredForVersion(2), DbTables.version2);
    expect(DbTables.requiredForVersion(3), DbTables.version2);
    expect(DbTables.requiredForVersion(4), DbTables.all);
    expect(DbTables.requiredForVersion(5), DbTables.all);
    expect(DbTables.version1, isNot(contains(DbTables.purchases)));
    expect(DbTables.version2, isNot(contains(DbTables.returns)));
    expect(DbTables.all, containsAll(DbTables.version2));
  });

  test('the returns migration adds both tables', () {
    final upgrade = DbSchema.upgradeTo4.join('; ');
    expect(upgrade, contains('CREATE TABLE returns'));
    expect(upgrade, contains('CREATE TABLE return_items'));
    expect(upgrade, contains('idx_returns_invoice'));
    expect(upgrade, contains('REFERENCES invoice_items (id) ON DELETE SET NULL'));
  });

  test('the settlement marker is added without touching the credit', () {
    final upgrade = DbSchema.upgradeTo5.join('; ');
    expect(upgrade, contains('ADD COLUMN settled_at'));
    expect(upgrade, isNot(contains('refund_cents')));
    final returns = DbSchema.createStatements.firstWhere(
      (statement) => statement.contains('CREATE TABLE returns'),
    );
    expect(returns, contains('settled_at TEXT NOT NULL DEFAULT \'\''));
  });

  test('the database version matches the latest schema', () {
    expect(AppConstants.databaseVersion, 5);
  });
}
