import 'dart:convert';

import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';

/// An invoice that still has to reach Telegram and/or the PC.
///
/// Each delivery is tracked separately, so a phone that reaches Telegram but
/// not the PC retries only the PC on the next attempt (no double messages).
final class OutboxEntry {
  const OutboxEntry({
    required this.invoiceId,
    this.telegramDone = false,
    this.desktopDone = false,
  });

  factory OutboxEntry.fromJson(Map<String, Object?> json) => OutboxEntry(
    invoiceId: (json['invoiceId'] as num).toInt(),
    telegramDone: json['telegramDone'] == true,
    desktopDone: json['desktopDone'] == true,
  );

  final int invoiceId;
  final bool telegramDone;
  final bool desktopDone;

  bool get isDone => telegramDone && desktopDone;

  OutboxEntry copyWith({bool? telegramDone, bool? desktopDone}) => OutboxEntry(
    invoiceId: invoiceId,
    telegramDone: telegramDone ?? this.telegramDone,
    desktopDone: desktopDone ?? this.desktopDone,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'invoiceId': invoiceId,
    'telegramDone': telegramDone,
    'desktopDone': desktopDone,
  };
}

/// The queue of invoices that could not be delivered yet.
class SyncOutbox {
  SyncOutbox(this._store);

  final KeyValueStore _store;

  static const String _key = 'sync.outbox';

  Future<List<OutboxEntry>> load() async {
    final raw = await _store.getString(_key);
    if (raw == null || raw.isEmpty) return const <OutboxEntry>[];
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return decoded
          .whereType<Map<String, Object?>>()
          .map(OutboxEntry.fromJson)
          .toList();
    } on FormatException {
      return const <OutboxEntry>[];
    }
  }

  Future<void> save(List<OutboxEntry> entries) => _store.setString(
    _key,
    jsonEncode(entries.map((entry) => entry.toJson()).toList()),
  );
}
