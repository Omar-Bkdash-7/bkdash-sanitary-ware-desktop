/// One finished exchange with the phone, remembered for the status card.
final class SyncEvent {
  const SyncEvent({
    required this.at,
    required this.fileName,
    required this.invoices,
    required this.customers,
    required this.products,
    this.purchases = 0,
    this.note = '',
  });

  factory SyncEvent.fromJson(Map<String, Object?> json) => SyncEvent(
    at:
        DateTime.tryParse((json['at'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    fileName: (json['file'] as String?) ?? '',
    invoices: (json['invoices'] as num?)?.toInt() ?? 0,
    customers: (json['customers'] as num?)?.toInt() ?? 0,
    products: (json['products'] as num?)?.toInt() ?? 0,
    purchases: (json['purchases'] as num?)?.toInt() ?? 0,
    note: (json['note'] as String?) ?? '',
  );

  final DateTime at;
  final String fileName;
  final int invoices;
  final int customers;
  final int products;
  final int purchases;

  /// For an import, the verdict that was shown before the user confirmed.
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.toIso8601String(),
    'file': fileName,
    'invoices': invoices,
    'customers': customers,
    'products': products,
    'purchases': purchases,
    'note': note,
  };
}

/// What the status card shows about the last exchanges.
final class PhoneSyncState {
  const PhoneSyncState({this.lastImport, this.lastExport});

  /// The last file imported from the phone.
  final SyncEvent? lastImport;

  /// The last database copy sent by hand ("send now").
  final SyncEvent? lastExport;
}
