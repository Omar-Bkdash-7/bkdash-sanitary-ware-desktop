import 'dart:async';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/data/desktop_sync_service.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/data/invoice_repository.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';

/// The "new invoice" screen: edits an [InvoiceDraft] and saves it.
class CreateInvoiceController extends BaseController {
  CreateInvoiceController({
    required ItemRepository items,
    required CustomerRepository customers,
    required InvoiceRepository invoices,
    DesktopSyncService? sync,
    this.invoiceId,
  }) : _items = items,
       _customers = customers,
       _invoices = invoices,
       _sync = sync;

  final ItemRepository _items;
  final CustomerRepository _customers;
  final InvoiceRepository _invoices;

  /// Sends the saved invoice to Telegram and to the computer.
  final DesktopSyncService? _sync;

  /// The invoice being rewritten; `null` while a new one is written.
  final int? invoiceId;

  bool get isEditing => invoiceId != null;

  InvoiceDraft _draft = const InvoiceDraft();
  List<Item> _catalog = const <Item>[];
  List<Customer> _customerList = const <Customer>[];
  bool _saving = false;

  InvoiceDraft get draft => _draft;

  /// Products that can be added (everything in stock first).
  List<Item> get catalog => _catalog;
  List<Customer> get customers => _customerList;
  bool get isSaving => _saving;

  Future<void> load() => runLoad(() async {
    _catalog = await _items.getAll();
    final summaries = await _customers.getAllWithSummary();
    _customerList = summaries.map((summary) => summary.customer).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final id = invoiceId;
    if (id != null) _draft = await _draftFromSaved(id);
  });

  /// Rebuilds the draft of an invoice that was already issued.
  ///
  /// The lines are matched to the catalog by their SKU, because an invoice line
  /// keeps its own copy of the name and the prices. A product that left the
  /// inventory makes the invoice un-editable: its pieces could not be given
  /// back to the right row.
  Future<InvoiceDraft> _draftFromSaved(int id) async {
    final details = await _invoices.getDetails(id);
    if (details == null) throw const NotFoundException('الفاتورة غير موجودة.');
    final byId = <int, Item>{for (final item in _catalog) item.id: item};
    // The same SKU may exist in more than one container: match the pair.
    final bySku = <String, Item>{
      for (final item in _catalog) '${item.sku}|${item.container}': item,
    };
    final lines = <InvoiceLine>[];
    for (final line in details.lines) {
      final item =
          byId[line.itemId] ?? bySku['${line.sku}|${line.container}'];
      if (item == null) {
        throw const ValidationException(
          'أحد أصناف هذه الفاتورة لم يعد في المخزون، فلا يمكن تعديلها. '
          'احذف الفاتورة وأصدر واحدة جديدة.',
        );
      }
      lines.add(
        InvoiceLine(
          itemId: item.id,
          itemName: line.itemName,
          category: line.category,
          sku: line.sku,
          container: line.container,
          unit: line.unit,
          quantity: line.quantity,
          unitCost: line.unitCost,
          unitPrice: line.unitPrice,
          // The pieces of this invoice come back before the new ones are taken.
          available: item.quantity + line.quantity,
        ),
      );
    }
    final invoice = details.invoice;
    final customerId = invoice.customerId;
    Customer? customer;
    if (customerId != null) {
      for (final candidate in _customerList) {
        if (candidate.id == customerId) {
          customer = candidate;
          break;
        }
      }
    }
    return InvoiceDraft(
      customer: customer,
      paymentMethod: invoice.paymentMethod,
      lines: lines,
      partialPaid: invoice.paid,
      notes: invoice.notes,
    );
  }

  /// Registers a new customer and selects him for this invoice.
  Future<void> addCustomer(CustomerInput input) async {
    final created = await _customers.create(input);
    _customerList = [..._customerList, created]
      ..sort((a, b) => a.name.compareTo(b.name));
    _draft = _draft.copyWith(customer: created);
    notifyListeners();
  }

  void selectCustomer(Customer? customer) {
    _draft = customer == null
        ? _draft.copyWith(clearCustomer: true)
        : _draft.copyWith(customer: customer);
    notifyListeners();
  }

  void setPaymentMethod(PaymentMethod method) {
    _draft = _draft.copyWith(paymentMethod: method);
    notifyListeners();
  }

  void setPartialPaid(Money amount) {
    _draft = _draft.copyWith(partialPaid: amount);
    notifyListeners();
  }

  void setNotes(String notes) => _draft = _draft.copyWith(notes: notes);

  /// Adds one piece of [item]; throws [InsufficientStockException] when the
  /// stock does not allow it.
  void addItem(Item item) {
    final index = _draft.lines.indexWhere((line) => line.itemId == item.id);
    final inInvoice = index == -1 ? 0 : _draft.lines[index].quantity;
    if (inInvoice + 1 > item.quantity) {
      throw InsufficientStockException(
        itemName: item.name,
        available: item.quantity,
        requested: inInvoice + 1,
      );
    }
    _draft = _draft.addItem(item);
    notifyListeners();
  }

  /// Changes a line quantity; throws [InsufficientStockException] above stock.
  void setLineQuantity(int index, int quantity) {
    final line = _draft.lines[index];
    if (quantity < 1) {
      throw const ValidationException('الكمية يجب أن تكون 1 على الأقل.');
    }
    if (quantity > line.available) {
      throw InsufficientStockException(
        itemName: line.itemName,
        available: line.available,
        requested: quantity,
      );
    }
    _draft = _draft.updateLine(index, quantity: quantity);
    notifyListeners();
  }

  void setLineUnitPrice(int index, Money price) {
    _draft = _draft.updateLine(index, unitPrice: price);
    notifyListeners();
  }

  void removeLine(int index) {
    _draft = _draft.removeLine(index);
    notifyListeners();
  }

  /// Saves the invoice and returns its number (creating or updating it).
  Future<int> save() async {
    _saving = true;
    notifyListeners();
    try {
      final editing = invoiceId;
      if (editing != null) {
        await _invoices.update(editing, _draft);
        return editing;
      }
      final id = await _invoices.create(_draft);
      // The delivery runs on its own: a slow network never blocks the sale.
      final sync = _sync;
      if (sync != null) unawaited(sync.onInvoiceCreated(id));
      return id;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
