import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/payment_repository.dart';

class CustomersController extends BaseController {
  CustomersController({
    required CustomerRepository customers,
    required PaymentRepository payments,
    required DataChangeNotifier changes,
  }) : _customers = customers,
       _payments = payments,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final CustomerRepository _customers;
  final PaymentRepository _payments;
  final DataChangeNotifier _changes;

  List<CustomerSummary> _all = const <CustomerSummary>[];
  String _query = '';
  bool _onlyDebtors = false;

  List<CustomerSummary> get all => _all;
  bool get onlyDebtors => _onlyDebtors;

  List<CustomerSummary> get visible {
    final query = normalizeForSearch(_query);
    return _all.where((summary) {
      if (_onlyDebtors && !summary.hasDebt) return false;
      if (query.isEmpty) return true;
      return normalizeForSearch(summary.customer.name).contains(query) ||
          summary.customer.phone.contains(query);
    }).toList();
  }

  /// What all customers owe together.
  Money get totalDebt => Money.sum(_all.map((summary) => summary.debt));

  int get debtorCount => _all.where((summary) => summary.hasDebt).length;

  Future<void> load() => runLoad(() async {
    _all = await _customers.getAllWithSummary();
  });

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  void setOnlyDebtors({required bool value}) {
    _onlyDebtors = value;
    notifyListeners();
  }

  Future<Customer> addCustomer(CustomerInput input) => _customers.create(input);

  Future<void> updateCustomer(int id, CustomerInput input) =>
      _customers.update(id, input);

  Future<void> deleteCustomer(int id) => _customers.delete(id);

  Future<void> receivePayment({
    required int customerId,
    required Money amount,
    String note = '',
  }) => _payments.receiveCustomerPayment(
    customerId: customerId,
    amount: amount,
    note: note,
  );

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
