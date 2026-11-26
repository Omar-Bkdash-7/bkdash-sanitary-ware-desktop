import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/import_planner.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/db_key_sets.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/import_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const DataSummary _summary = DataSummary(
  invoices: 0,
  customers: 0,
  products: 0,
  purchases: 0,
  schemaVersion: 2,
);

DbKeySets _keys({
  Map<String, String> invoices = const <String, String>{},
  Map<String, String> customers = const <String, String>{},
  Map<String, String> items = const <String, String>{},
  Map<String, String> receipts = const <String, String>{},
  Map<String, String> purchases = const <String, String>{},
  Map<String, String> payouts = const <String, String>{},
}) => DbKeySets(
  invoices: invoices,
  customers: customers,
  items: items,
  receipts: receipts,
  purchases: purchases,
  payouts: payouts,
);

ImportPlan _plan(DbKeySets local, DbKeySets incoming) =>
    ImportPlanner.compare(
      local: local,
      incoming: incoming,
      current: _summary,
      incomingSummary: _summary,
    );

Map<String, String> _invoices(List<String> ids, {String signature = 'a'}) => {
  for (final id in ids) id: signature,
};

const Map<String, String> _catalogue = <String, String>{
  '1|SKU-1': 'pipe|cat|1000|1500|50',
  '2|SKU-2': 'tap|cat|2000|3000|20',
};

void main() {
  group('ImportPlanner', () {
    test('a computer with only the starting catalogue can import freely', () {
      final plan = _plan(
        _keys(items: _catalogue),
        _keys(
          items: _catalogue,
          invoices: _invoices(<String>['1|t1', '2|t2']),
        ),
      );
      expect(plan.verdict, ImportVerdict.freshLocal);
      expect(plan.isSafe, isTrue);
      expect(plan.needsStrongWarning, isFalse);
    });

    test('the same data on both sides changes nothing', () {
      final side = _keys(
        items: _catalogue,
        invoices: _invoices(<String>['1|t1', '2|t2']),
      );
      final plan = _plan(side, side);
      expect(plan.verdict, ImportVerdict.identical);
      expect(plan.lost.isEmpty, isTrue);
      expect(plan.gained.isEmpty, isTrue);
    });

    test('a file with everything here and more is a normal catch-up', () {
      final plan = _plan(
        _keys(items: _catalogue, invoices: _invoices(<String>['1|t1', '2|t2'])),
        _keys(
          items: _catalogue,
          invoices: _invoices(<String>['1|t1', '2|t2', '3|t3']),
        ),
      );
      expect(plan.verdict, ImportVerdict.incomingNewer);
      expect(plan.gained.invoices, 1);
      expect(plan.lost.isEmpty, isTrue);
      expect(plan.isSafe, isTrue);
    });

    test('an older file would delete what was added here', () {
      final plan = _plan(
        _keys(
          items: _catalogue,
          invoices: _invoices(<String>['1|t1', '2|t2', '3|t3']),
        ),
        _keys(items: _catalogue, invoices: _invoices(<String>['1|t1', '2|t2'])),
      );
      expect(plan.verdict, ImportVerdict.incomingOlder);
      expect(plan.lost.invoices, 1);
      expect(plan.gained.isEmpty, isTrue);
      expect(plan.needsStrongWarning, isTrue);
      expect(plan.isSafe, isFalse);
    });

    test('two different invoices with the same number are a divergence', () {
      // Invoice 3 was made on the computer at 09:00 and on the phone at 09:30.
      final plan = _plan(
        _keys(
          items: _catalogue,
          invoices: _invoices(<String>['1|t1', '2|t2', '3|09:00']),
        ),
        _keys(
          items: _catalogue,
          invoices: _invoices(<String>['1|t1', '2|t2', '3|09:30']),
        ),
      );
      expect(plan.verdict, ImportVerdict.diverged);
      expect(plan.lost.invoices, 1);
      expect(plan.gained.invoices, 1);
      expect(plan.needsStrongWarning, isTrue);
    });

    test('the same records edited on one side are reported as edited', () {
      final plan = _plan(
        _keys(
          items: _catalogue,
          invoices: _invoices(<String>['1|t1'], signature: 'total=3000'),
        ),
        _keys(
          items: _catalogue,
          invoices: _invoices(<String>['1|t1'], signature: 'total=9999'),
        ),
      );
      expect(plan.verdict, ImportVerdict.edited);
      expect(plan.changed.invoices, 1);
      expect(plan.needsStrongWarning, isFalse);
    });

    test('a receipt taken on the phone counts as news', () {
      final plan = _plan(
        _keys(items: _catalogue, customers: <String, String>{'1|c1': 'Ali'}),
        _keys(
          items: _catalogue,
          customers: <String, String>{'1|c1': 'Ali'},
          receipts: <String, String>{'1|1|t9': '500|'},
        ),
      );
      expect(plan.verdict, ImportVerdict.incomingNewer);
      expect(plan.gained.receipts, 1);
    });

    test('a purchase made on the phone counts as news', () {
      final plan = _plan(
        _keys(items: _catalogue, customers: <String, String>{'1|c1': 'Ali'}),
        _keys(
          items: _catalogue,
          customers: <String, String>{'1|c1': 'Ali'},
          purchases: <String, String>{'1|t9': '1|Ali|2026-11-10|5000|2000|'},
        ),
      );
      expect(plan.verdict, ImportVerdict.incomingNewer);
      expect(plan.gained.purchases, 1);
    });

    test('a payout made on the phone counts as news', () {
      final plan = _plan(
        _keys(items: _catalogue, customers: <String, String>{'1|c1': 'Ali'}),
        _keys(
          items: _catalogue,
          customers: <String, String>{'1|c1': 'Ali'},
          payouts: <String, String>{'1|1|t9': '1000|'},
        ),
      );
      expect(plan.verdict, ImportVerdict.incomingNewer);
      expect(plan.gained.payouts, 1);
    });

    test('a purchase that exists only here would be lost', () {
      final plan = _plan(
        _keys(
          items: _catalogue,
          customers: <String, String>{'1|c1': 'Ali'},
          purchases: <String, String>{'1|t9': '1|Ali|2026-11-10|5000|2000|'},
        ),
        _keys(items: _catalogue, customers: <String, String>{'1|c1': 'Ali'}),
      );
      expect(plan.verdict, ImportVerdict.incomingOlder);
      expect(plan.lost.purchases, 1);
      expect(plan.needsStrongWarning, isTrue);
    });

    test('a purchase alone makes the database non-fresh', () {
      expect(
        _keys(
          purchases: <String, String>{'1|t9': '1|Ali|2026-11-10|5000|2000|'},
        ).hasUserData,
        isTrue,
      );
      expect(
        _keys(payouts: <String, String>{'1|1|t9': '1000|'}).hasUserData,
        isTrue,
      );
    });

    test('an item that exists only here is a loss', () {
      final plan = _plan(
        _keys(
          items: <String, String>{..._catalogue, '3|SKU-3': 'valve|cat|1|2|3'},
          invoices: _invoices(<String>['1|t1']),
        ),
        _keys(items: _catalogue, invoices: _invoices(<String>['1|t1'])),
      );
      expect(plan.verdict, ImportVerdict.incomingOlder);
      expect(plan.lost.items, 1);
    });

    test('only the records of a real sale decide whether data is fresh', () {
      expect(_keys(items: _catalogue).hasUserData, isFalse);
      expect(
        _keys(customers: <String, String>{'1|c': 'x'}).hasUserData,
        isTrue,
      );
    });

    test('the plan remembers where the file came from', () {
      final plan = ImportPlanner.compare(
        local: _keys(),
        incoming: _keys(),
        current: _summary,
        incomingSummary: _summary,
        fileName: 'bkdash_desktop_2026-11-16_09-41.db',
        fromThisComputer: true,
      );
      expect(plan.fromThisComputer, isTrue);
      expect(plan.fileName, 'bkdash_desktop_2026-11-16_09-41.db');
    });
  });
}
