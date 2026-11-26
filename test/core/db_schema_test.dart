import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every table is created and the purchase tables are part of version 2',
    () {
      final schema = DbSchema.createStatements.join('\n');
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

  test('a version 1 backup stays valid after purchases were added', () {
    expect(DbTables.requiredForVersion(1), DbTables.version1);
    expect(DbTables.requiredForVersion(2), DbTables.all);
    expect(DbTables.version1, isNot(contains(DbTables.purchases)));
    expect(DbTables.all, containsAll(DbTables.version1));
  });

  test('the database version matches the latest schema', () {
    expect(AppConstants.databaseVersion, 2);
  });
}
