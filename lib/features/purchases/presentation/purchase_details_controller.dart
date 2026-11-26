import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';

/// One purchase with its lines and payments.
class PurchaseDetailsController extends BaseController {
  PurchaseDetailsController({
    required this.purchaseId,
    required PurchaseRepository repository,
    required DataChangeNotifier changes,
  }) : _repository = repository,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final int purchaseId;
  final PurchaseRepository _repository;
  final DataChangeNotifier _changes;

  PurchaseDetails? _details;

  /// `null` when the purchase does not exist.
  PurchaseDetails? get details => _details;

  Future<void> load() => runLoad(() async {
    _details = await _repository.getDetails(purchaseId);
  });

  /// Deletes the purchase; the stock goes back to what it was before it, as
  /// long as nothing was sold from the bought pieces or paid later.
  Future<void> deletePurchase() => _repository.delete(purchaseId);

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
