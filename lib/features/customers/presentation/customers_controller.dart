import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/payment_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';

class CustomersController extends BaseController {
  CustomersController({
    required CustomerRepository customers,
    required PaymentRepository payments,
    required PurchaseRepository purchases,
    required DataChangeNotifier changes,
  }) : _customers = customers,
       _payments = payments,
       _purchases = purchases,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final CustomerRepository _customers;
  final PaymentRepository _payments;
  final PurchaseRepository _purchases;
  final DataChangeNotifier _changes;

  List<CustomerSummary> _all = const <CustomerSummary>[];
  String _query = '';
  bool _onlyOpen = false;

  List<CustomerSummary> get all => _all;
  bool get onlyOpen => _onlyOpen;

  List<CustomerSummary> get visible {
    final query = normalizeForSearch(_query);
    return _all.where((summary) {
      if (_onlyOpen && !summary.hasBalance) return false;
      if (query.isEmpty) return true;
      return normalizeForSearch(summary.customer.name).contains(query) ||
          summary.customer.phone.contains(query);
    }).toList();
  }

  /// What all customers owe the shop (positive net balances only).
  Money get totalReceivable =>
      Money.sum(_all.map((summary) => summary.amountDue));

  /// What the shop owes all customers (negative net balances only).
  Money get totalPayable =>
      Money.sum(_all.map((summary) => summary.amountPayable));

  /// The two sides together; positive means the customers owe more.
  Money get netBalance => totalReceivable - totalPayable;

  int get debtorCount => _all.where((summary) => summary.customerOwes).length;

  int get creditorCount => _all.where((summary) => summary.weOwe).length;

  Future<void> load() => runLoad(() async {
    _all = await _customers.getAllWithSummary();
  });

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  void setOnlyOpen({required bool value}) {
    _onlyOpen = value;
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

  Future<void> payCustomer({
    required int customerId,
    required Money amount,
    String note = '',
  }) => _purchases.payCustomer(
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
