import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/payment_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';

/// The account statement of one customer.
class CustomerDetailsController extends BaseController {
  CustomerDetailsController({
    required this.customerId,
    required CustomerRepository customers,
    required InvoiceRepository invoices,
    required PaymentRepository payments,
    required DataChangeNotifier changes,
  }) : _customers = customers,
       _invoices = invoices,
       _payments = payments,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final int customerId;
  final CustomerRepository _customers;
  final InvoiceRepository _invoices;
  final PaymentRepository _payments;
  final DataChangeNotifier _changes;

  CustomerSummary? _summary;
  List<Invoice> _invoiceList = const <Invoice>[];
  List<CustomerReceipt> _receipts = const <CustomerReceipt>[];

  /// `null` once the customer was deleted.
  CustomerSummary? get summary => _summary;
  List<Invoice> get invoices => _invoiceList;
  List<CustomerReceipt> get receipts => _receipts;

  Future<void> load() => runLoad(() async {
    _summary = await _customers.getSummary(customerId);
    _invoiceList = await _invoices.getInvoices(customerId: customerId);
    _receipts = await _payments.receiptsFor(customerId);
  });

  Future<void> receivePayment(Money amount, {String note = ''}) =>
      _payments.receiveCustomerPayment(
        customerId: customerId,
        amount: amount,
        note: note,
      );

  Future<void> update(CustomerInput input) =>
      _customers.update(customerId, input);

  Future<void> delete() => _customers.delete(customerId);

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
