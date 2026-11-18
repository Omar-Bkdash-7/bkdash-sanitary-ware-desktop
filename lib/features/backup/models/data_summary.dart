/// How much data a database file holds.
///
/// Shown in the restore confirmation, so the user sees what he is about to
/// replace and what he is about to get, before anything is overwritten.
final class DataSummary {
  const DataSummary({
    required this.invoices,
    required this.customers,
    required this.products,
    required this.schemaVersion,
  });

  /// `true` for a phone that has no data yet (a fresh install).
  static const DataSummary empty = DataSummary(
    invoices: 0,
    customers: 0,
    products: 0,
    schemaVersion: 0,
  );

  final int invoices;
  final int customers;
  final int products;

  /// `PRAGMA user_version` of the file (0 for an empty summary).
  final int schemaVersion;
}
