import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/db_key_sets.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/import_plan.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/snapshot_meta.dart';

/// Decides whether importing a database file is safe.
///
/// A restore replaces *everything* on this computer with the file. That is the
/// right thing when the file is the phone's newer copy, and a disaster when the
/// file is older than the data here, or when both devices were used since the
/// last exchange. The planner tells those cases apart by comparing which
/// records each side holds (see [DbKeySets]), so it needs no marker inside the
/// database and works with the phone app exactly as it is today.
abstract final class ImportPlanner {
  static ImportPlan compare({
    required DbKeySets local,
    required DbKeySets incoming,
    required DataSummary current,
    required DataSummary incomingSummary,
    String fileName = '',
    SnapshotMeta? meta,
    bool fromThisComputer = false,
  }) {
    final lost = RecordTally(
      invoices: _missing(local.invoices, incoming.invoices),
      customers: _missing(local.customers, incoming.customers),
      items: _missing(local.items, incoming.items),
      receipts: _missing(local.receipts, incoming.receipts),
      purchases: _missing(local.purchases, incoming.purchases),
      payouts: _missing(local.payouts, incoming.payouts),
    );
    final gained = RecordTally(
      invoices: _missing(incoming.invoices, local.invoices),
      customers: _missing(incoming.customers, local.customers),
      items: _missing(incoming.items, local.items),
      receipts: _missing(incoming.receipts, local.receipts),
      purchases: _missing(incoming.purchases, local.purchases),
      payouts: _missing(incoming.payouts, local.payouts),
    );
    final changed = RecordTally(
      invoices: _different(local.invoices, incoming.invoices),
      customers: _different(local.customers, incoming.customers),
      items: _different(local.items, incoming.items),
      receipts: _different(local.receipts, incoming.receipts),
      purchases: _different(local.purchases, incoming.purchases),
      payouts: _different(local.payouts, incoming.payouts),
    );

    final ImportVerdict verdict;
    if (!local.hasUserData) {
      verdict = ImportVerdict.freshLocal;
    } else if (lost.isEmpty && gained.isEmpty) {
      verdict = changed.isEmpty
          ? ImportVerdict.identical
          : ImportVerdict.edited;
    } else if (lost.isEmpty) {
      verdict = ImportVerdict.incomingNewer;
    } else if (gained.isEmpty) {
      verdict = ImportVerdict.incomingOlder;
    } else {
      verdict = ImportVerdict.diverged;
    }

    return ImportPlan(
      verdict: verdict,
      fileName: fileName,
      current: current,
      incoming: incomingSummary,
      currentReceipts: local.receipts.length,
      incomingReceipts: incoming.receipts.length,
      currentPayouts: local.payouts.length,
      incomingPayouts: incoming.payouts.length,
      lost: lost,
      gained: gained,
      changed: changed,
      localLastActivity: local.lastActivity,
      incomingLastActivity: incoming.lastActivity,
      meta: meta,
      fromThisComputer: fromThisComputer,
    );
  }

  /// How many identities of [from] are absent from [other].
  static int _missing(Map<String, String> from, Map<String, String> other) {
    var count = 0;
    for (final key in from.keys) {
      if (!other.containsKey(key)) count++;
    }
    return count;
  }

  /// How many identities exist on both sides with a different signature.
  static int _different(Map<String, String> a, Map<String, String> b) {
    var count = 0;
    a.forEach((key, signature) {
      final other = b[key];
      if (other != null && other != signature) count++;
    });
    return count;
  }
}
