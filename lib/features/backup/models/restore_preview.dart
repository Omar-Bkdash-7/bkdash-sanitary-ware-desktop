import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';

/// What the phone holds now and what the chosen file holds, side by side.
final class RestorePreview {
  const RestorePreview({required this.current, required this.incoming});

  final DataSummary current;
  final DataSummary incoming;
}
