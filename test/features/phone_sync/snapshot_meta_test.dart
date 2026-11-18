import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/snapshot_meta.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/backup_caption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapshotMeta', () {
    test('reads the line that the phone puts under every database upload', () {
      final caption = BackupCaption.database(
        sentAt: DateTime(2026, 11, 16, 9, 41, 12),
        summary: const DataSummary(
          invoices: 250,
          customers: 87,
          products: 312,
          schemaVersion: 1,
        ),
        fileName: 'bkdash_2026-11-16_09-41.db',
      );
      final meta = SnapshotMeta.tryParse(caption);
      expect(meta, isNotNull);
      expect(meta!.formatVersion, 1);
      expect(meta.schemaVersion, 1);
      expect(meta.invoices, 250);
      expect(meta.customers, 87);
      expect(meta.products, 312);
      expect(meta.sentAt, DateTime(2026, 11, 16, 9, 41, 12));
    });

    test('ignores keys it does not know', () {
      final meta = SnapshotMeta.tryParse(
        '🗄 نسخة\n#bkdash_sync v=1 schema=2 invoices=3 customers=4 '
        'products=5 device=desktop future=yes',
      );
      expect(meta, isNotNull);
      expect(meta!.schemaVersion, 2);
      expect(meta.products, 5);
    });

    test('returns null when there is no line or it is damaged', () {
      expect(SnapshotMeta.tryParse(null), isNull);
      expect(SnapshotMeta.tryParse(''), isNull);
      expect(SnapshotMeta.tryParse('just a note'), isNull);
      expect(SnapshotMeta.tryParse('#bkdash_sync schema=1 invoices=3'), isNull);
    });
  });
}
