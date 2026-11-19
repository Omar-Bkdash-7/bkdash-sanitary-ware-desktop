import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/phone_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/phone_sync_state.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_queue_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/sync_job.dart';

/// The "Sync with phone" screen: what was exchanged last, and the button that
/// sends this computer's database to the phone.
class SyncCenterController extends BaseController {
  SyncCenterController({
    required PhoneSyncService service,
    required SyncQueueStore queue,
    required DataChangeNotifier changes,
  }) : _service = service,
       _queue = queue,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final PhoneSyncService _service;
  final SyncQueueStore _queue;
  final DataChangeNotifier _changes;

  bool _telegramReady = false;
  PhoneSyncState _state = const PhoneSyncState();
  DataSummary? _summary;
  DateTime? _lastAutoSent;
  String? _info;
  bool _busy = false;

  /// The bot token and chat are filled in.
  bool get telegramReady => _telegramReady;

  PhoneSyncState get state => _state;

  /// Counts of what this computer holds now.
  DataSummary? get summary => _summary;

  /// When the background delivery last uploaded a database copy.
  DateTime? get lastAutoSent => _lastAutoSent;

  /// The last thing that happened, shown under the buttons.
  String? get info => _info;

  bool get isBusy => _busy;

  /// This computer has neither sales nor customers: the first thing to do is to
  /// bring the phone's data here.
  bool get looksUnused {
    final summary = _summary;
    return summary != null && summary.invoices == 0 && summary.customers == 0;
  }

  Future<void> load() => runLoad(_reload);

  Future<void> refresh() => load();

  Future<void> sendNow() => _guard(() async {
    final event = await _service.sendSnapshotNow();
    _info =
        'أُرسلت نسخة كاملة (${event.invoices} فاتورة، '
        '${event.customers} زبون) إلى Telegram.';
    await _reload();
  });

  Future<void> _reload() async {
    _telegramReady = await _service.isTelegramConfigured();
    _state = await _service.loadState();
    _summary = await _service.currentSummary();
    DateTime? sent;
    for (final job in await _queue.recent()) {
      if (job.kind == SyncJobKind.database &&
          job.status == SyncJobStatus.sent) {
        sent = job.createdAt;
        break;
      }
    }
    _lastAutoSent = sent;
  }

  void _onDataChanged() {
    if (!isDisposed) unawaited(load());
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    _busy = true;
    _info = null;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
