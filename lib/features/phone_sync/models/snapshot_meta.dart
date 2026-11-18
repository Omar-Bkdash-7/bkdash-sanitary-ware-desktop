import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';

/// What the machine-readable last line of a database caption says.
///
/// The phone and the computer both end the caption of a database upload with
///
///     #bkdash_sync v=1 schema=1 ts=2026-11-16T09:41:12 invoices=250
///     customers=87 products=312
///
/// (one single line). Reading it lets the computer show what a Telegram file
/// holds before it is downloaded. Keys it does not know are ignored, so a later
/// version of the line can add fields without breaking this reader.
final class SnapshotMeta {
  const SnapshotMeta({
    required this.formatVersion,
    required this.schemaVersion,
    required this.sentAt,
    required this.invoices,
    required this.customers,
    required this.products,
  });

  /// `v=`: the shape of the line itself.
  final int formatVersion;

  /// `schema=`: `PRAGMA user_version` of the database that was sent.
  final int schemaVersion;

  /// `ts=`: when the phone or computer built the file (local time).
  final DateTime? sentAt;

  final int invoices;
  final int customers;
  final int products;

  DataSummary get summary => DataSummary(
    invoices: invoices,
    customers: customers,
    products: products,
    schemaVersion: schemaVersion,
  );

  static final RegExp _marker = RegExp(
    r'#bkdash_sync((?:[ \t]+[A-Za-z_]+=\S*)+)',
  );

  /// The line found in [caption], or `null` when there is none.
  static SnapshotMeta? tryParse(String? caption) {
    if (caption == null || caption.isEmpty) return null;
    final match = _marker.firstMatch(caption);
    if (match == null) return null;

    final values = <String, String>{};
    for (final token in match.group(1)!.trim().split(RegExp(r'\s+'))) {
      final index = token.indexOf('=');
      if (index > 0) {
        values[token.substring(0, index)] = token.substring(index + 1);
      }
    }
    final version = int.tryParse(values['v'] ?? '');
    if (version == null) return null;
    final stamp = values['ts'];
    return SnapshotMeta(
      formatVersion: version,
      schemaVersion: int.tryParse(values['schema'] ?? '') ?? 0,
      sentAt: stamp == null ? null : AppDates.tryParse(stamp),
      invoices: int.tryParse(values['invoices'] ?? '') ?? 0,
      customers: int.tryParse(values['customers'] ?? '') ?? 0,
      products: int.tryParse(values['products'] ?? '') ?? 0,
    );
  }
}
