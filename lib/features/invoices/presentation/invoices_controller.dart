import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';

enum InvoiceFilter {
  all('الكل'),
  unpaid('عليها ذمة'),
  paid('مسددة');

  const InvoiceFilter(this.label);

  final String label;
}

/// The list of issued invoices.
class InvoicesController extends BaseController {
  InvoicesController({
    required InvoiceRepository repository,
    required DataChangeNotifier changes,
  }) : _repository = repository,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final InvoiceRepository _repository;
  final DataChangeNotifier _changes;

  List<Invoice> _all = const <Invoice>[];
  InvoiceFilter _filter = InvoiceFilter.all;
  String _query = '';

  InvoiceFilter get filter => _filter;

  List<Invoice> get visible {
    final query = normalizeForSearch(_query);
    return _all.where((invoice) {
      switch (_filter) {
        case InvoiceFilter.all:
          break;
        case InvoiceFilter.unpaid:
          if (invoice.isSettled) return false;
        case InvoiceFilter.paid:
          if (!invoice.isSettled) return false;
      }
      if (query.isEmpty) return true;
      return normalizeForSearch(invoice.customerName).contains(query) ||
          invoice.id.toString() == query;
    }).toList();
  }

  Future<void> load() => runLoad(() async {
    _all = await _repository.getInvoices();
  });

  void setFilter(InvoiceFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
