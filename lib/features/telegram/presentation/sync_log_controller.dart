import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_coordinator.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/sync_queue_store.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/sync_job.dart';

/// The "send log" screen: the last deliveries and a manual retry.
class SyncLogController extends BaseController {
  SyncLogController({
    required SyncQueueStore queue,
    required SyncCoordinator coordinator,
  }) : _queue = queue,
       _coordinator = coordinator;

  final SyncQueueStore _queue;
  final SyncCoordinator _coordinator;

  List<SyncJob> _jobs = const <SyncJob>[];
  int _pending = 0;
  bool _busy = false;

  List<SyncJob> get jobs => _jobs;
  int get pending => _pending;
  bool get isBusy => _busy;

  Future<void> load() => runLoad(() async {
    _jobs = await _queue.recent();
    _pending = await _queue.pendingCount();
  });

  Future<void> retryNow() => _guard(() async {
    await _coordinator.retryNow();
    _jobs = await _queue.recent();
    _pending = await _queue.pendingCount();
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
