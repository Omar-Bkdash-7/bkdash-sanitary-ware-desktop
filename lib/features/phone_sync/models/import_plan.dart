import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/snapshot_meta.dart';

/// How a database file compares with the data on this computer.
enum ImportVerdict {
  /// Nothing differs: importing would change nothing.
  identical,

  /// This computer has no sales, customers or receipts yet, so nothing can be
  /// lost by replacing its data.
  freshLocal,

  /// The file holds everything this computer holds, and more: a normal
  /// catch-up with the other device.
  incomingNewer,

  /// The same records exist on both sides, but some of them were edited on one
  /// side. Which side is newer cannot be known from the files.
  edited,

  /// The file lacks records that exist here: importing it would delete them.
  incomingOlder,

  /// Each side holds records the other lacks: both devices were used without a
  /// sync in between. Importing keeps one side and drops the other.
  diverged,
}

/// How many records of each kind a comparison counted.
final class RecordTally {
  const RecordTally({
    this.invoices = 0,
    this.customers = 0,
    this.items = 0,
    this.receipts = 0,
    this.purchases = 0,
    this.payouts = 0,
    this.returns = 0,
  });

  final int invoices;
  final int customers;
  final int items;
  final int receipts;
  final int purchases;
  final int payouts;
  final int returns;

  int get total =>
      invoices +
      customers +
      items +
      receipts +
      purchases +
      payouts +
      returns;

  bool get isEmpty => total == 0;
}

/// The result of comparing an incoming database file with the local data.
final class ImportPlan {
  const ImportPlan({
    required this.verdict,
    required this.fileName,
    required this.current,
    required this.incoming,
    required this.currentReceipts,
    required this.incomingReceipts,
    required this.currentPayouts,
    required this.incomingPayouts,
    required this.currentReturns,
    required this.incomingReturns,
    required this.lost,
    required this.gained,
    required this.changed,
    required this.localLastActivity,
    required this.incomingLastActivity,
    this.meta,
    this.fromThisComputer = false,
  });

  final ImportVerdict verdict;
  final String fileName;

  /// Counts of the data on this computer now.
  final DataSummary current;

  /// Counts inside the incoming file.
  final DataSummary incoming;

  final int currentReceipts;
  final int incomingReceipts;
  final int currentPayouts;
  final int incomingPayouts;
  final int currentReturns;
  final int incomingReturns;

  /// Records here that the file lacks: importing deletes them.
  final RecordTally lost;

  /// Records in the file that are not here yet: importing adds them.
  final RecordTally gained;

  /// Records on both sides whose content differs: the file's version wins.
  final RecordTally changed;

  /// Newest invoice, receipt, purchase or payout on this computer
  /// ("2026-11-16T09:41:12").
  final String localLastActivity;

  /// Newest invoice, receipt, purchase or payout in the file.
  final String incomingLastActivity;

  /// The caption line the file travelled with, when it came from Telegram.
  final SnapshotMeta? meta;

  /// The file name says this very program produced it, not the phone.
  final bool fromThisComputer;

  /// Importing cannot lose anything that matters.
  bool get isSafe =>
      verdict == ImportVerdict.identical ||
      verdict == ImportVerdict.freshLocal ||
      verdict == ImportVerdict.incomingNewer;

  /// Importing deletes records that exist only here: the user must confirm that
  /// he understands before the button works.
  bool get needsStrongWarning =>
      verdict == ImportVerdict.incomingOlder ||
      verdict == ImportVerdict.diverged;
}
