import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';

/// One invoice with its lines and payments.
class InvoiceDetailsController extends BaseController {
  InvoiceDetailsController({
    required this.invoiceId,
    required InvoiceRepository repository,
    required DataChangeNotifier changes,
  }) : _repository = repository,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final int invoiceId;
  final InvoiceRepository _repository;
  final DataChangeNotifier _changes;

  InvoiceDetails? _details;

  /// `null` when the invoice does not exist.
  InvoiceDetails? get details => _details;

  Future<void> load() => runLoad(() async {
    _details = await _repository.getDetails(invoiceId);
  });

  /// Deletes the invoice; the stock and the customer balance go back to what
  /// they were before it was issued (one transaction).
  Future<void> deleteInvoice() => _repository.delete(invoiceId);

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
