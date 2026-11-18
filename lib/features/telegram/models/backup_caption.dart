import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';

/// The Arabic caption that travels with a database snapshot.
///
/// The last line is for the program that imports the file: it states the format
/// version, the schema version, the moment and how many records the file holds,
/// so a half-sent or unrelated file is refused before it is used.
abstract final class BackupCaption {
  /// Bumped only when the machine-readable line changes shape.
  static const int version = 1;

  static String database({
    required DateTime sentAt,
    required DataSummary summary,
    required String fileName,
  }) {
    return '🗄 نسخة قاعدة بيانات — بكداش\n'
        '📄 $fileName\n'
        '🕒 ${AppDates.display(sentAt)}  ${AppDates.time12(sentAt)}\n'
        '#bkdash_sync v=$version schema=${summary.schemaVersion} '
        'ts=${AppDates.isoDateTime(sentAt)} '
        'invoices=${summary.invoices} '
        'customers=${summary.customers} '
        'products=${summary.products}';
  }
}
