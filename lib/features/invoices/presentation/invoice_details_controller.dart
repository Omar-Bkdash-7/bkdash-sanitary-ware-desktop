import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/returns/data/return_repository.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';

/// One invoice with its lines, payments and returns.
class InvoiceDetailsController extends BaseController {
  InvoiceDetailsController({
    required this.invoiceId,
    required InvoiceRepository repository,
    required ReturnRepository returns,
    required DataChangeNotifier changes,
  }) : _repository = repository,
       _returns = returns,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final int invoiceId;
  final InvoiceRepository _repository;
  final ReturnRepository _returns;
  final DataChangeNotifier _changes;

  InvoiceDetails? _details;
  List<ReturnRecord> _returnList = const <ReturnRecord>[];

  /// `null` when the invoice does not exist.
  InvoiceDetails? get details => _details;

  /// The returns of this invoice, newest first.
  List<ReturnRecord> get returns => _returnList;

  /// Credit given back at the prices of the original sale.
  Money get returnedCredit =>
      Money.sum(_returnList.map((entry) => entry.total));

  /// Cash handed back with those returns.
  Money get refunded => Money.sum(_returnList.map((entry) => entry.refund));

  /// What the customer still owes after the returns (negative: the shop owes
  /// him that credit).
  Money get remainingAfterReturns {
    final details = _details;
    if (details == null) return Money.zero;
    return details.invoice.remaining - (returnedCredit - refunded);
  }

  Future<void> load() => runLoad(() async {
    _details = await _repository.getDetails(invoiceId);
    _returnList = await _returns.returnsForInvoice(invoiceId);
  });

  /// Deletes the invoice; the stock and the customer balance go back to what
  /// they were before it was issued (one transaction).
  Future<void> deleteInvoice() => _repository.delete(invoiceId);

  /// Deletes a return: its pieces leave the stock again and its credit
  /// disappears from the invoice and from the customer's balance.
  Future<void> deleteReturn(int id) => _returns.delete(id);

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
