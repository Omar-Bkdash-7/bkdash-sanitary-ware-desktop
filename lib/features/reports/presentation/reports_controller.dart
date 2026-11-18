import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/reports/data/report_repository.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';

class ReportsController extends BaseController {
  ReportsController({
    required ReportRepository repository,
    required DataChangeNotifier changes,
    Clock? clock,
  }) : _repository = repository,
       _changes = changes,
       _clock = clock ?? DateTime.now {
    _range = DateRange.forPeriod(_period, _clock());
    _changes.addListener(_onDataChanged);
  }

  final ReportRepository _repository;
  final DataChangeNotifier _changes;
  final Clock _clock;

  ReportPeriod _period = ReportPeriod.thisMonth;
  late DateRange _range;
  ReportData? _data;

  ReportPeriod get period => _period;
  DateRange get range => _range;

  /// `null` until the first load finished.
  ReportData? get data => _data;

  Future<void> load() => runLoad(() async {
    _data = await _repository.load(_range);
  });

  Future<void> selectPeriod(ReportPeriod period) {
    _period = period;
    _range = DateRange.forPeriod(period, _clock());
    return load();
  }

  Future<void> setCustomRange(DateRange range) {
    _period = ReportPeriod.custom;
    _range = range;
    return load();
  }

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
