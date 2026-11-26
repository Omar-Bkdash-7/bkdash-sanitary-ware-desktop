import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/data/customer_repository.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/purchases/data/purchase_repository.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_draft.dart';

/// The "buy from a customer" screen: edits a [PurchaseDraft] and saves it.
class CreatePurchaseController extends BaseController {
  CreatePurchaseController({
    required ItemRepository items,
    required CustomerRepository customers,
    required PurchaseRepository purchases,
    required Customer customer,
  }) : _items = items,
       _customers = customers,
       _purchases = purchases,
       _customer = customer,
       _draft = PurchaseDraft(customer: customer);

  final ItemRepository _items;
  final CustomerRepository _customers;
  final PurchaseRepository _purchases;

  Customer _customer;
  CustomerSummary? _summary;
  PurchaseDraft _draft;
  List<Item> _catalog = const <Item>[];
  bool _saving = false;

  Customer get customer => _customer;

  /// The customer with everything he still owes or is owed.
  CustomerSummary? get summary => _summary;
  PurchaseDraft get draft => _draft;

  /// Products already in the stock. Buying one adds to its quantity.
  List<Item> get catalog => _catalog;
  bool get isSaving => _saving;

  Future<void> load() => runLoad(() async {
    _catalog = await _items.getAll();
    // The name or the phone may have been edited since the card was drawn.
    final summary = await _customers.getSummary(_customer.id);
    if (summary == null) {
      throw const NotFoundException('الزبون غير موجود.');
    }
    _summary = summary;
    _customer = summary.customer;
  });

  /// Adds one piece of an item that is already in the stock.
  void addItem(Item item, {Money? unitCost}) {
    _draft = _draft.addItem(item, unitCost: unitCost);
    notifyListeners();
  }

  /// Adds a line for a product that is not in the stock yet.
  void addNewItem(PurchaseLine line) {
    _draft = _draft.addNewItem(line);
    notifyListeners();
  }

  void setLineQuantity(int index, int quantity) {
    if (quantity < 1) {
      throw const ValidationException('الكمية يجب أن تكون 1 على الأقل.');
    }
    _draft = _draft.updateLine(index, quantity: quantity);
    notifyListeners();
  }

  void setLineUnitCost(int index, Money cost) {
    if (cost.isNegative) {
      throw const ValidationException(AppStrings.invalidAmount);
    }
    _draft = _draft.updateLine(index, unitCost: cost);
    notifyListeners();
  }

  void setLineSalePrice(int index, Money price) {
    if (price.isNegative) {
      throw const ValidationException(AppStrings.invalidAmount);
    }
    _draft = _draft.updateLine(index, salePrice: price);
    notifyListeners();
  }

  void removeLine(int index) {
    _draft = _draft.removeLine(index);
    notifyListeners();
  }

  void setPaidNow(Money amount) {
    _draft = _draft.copyWith(paidNow: amount);
    notifyListeners();
  }

  void setNotes(String notes) => _draft = _draft.copyWith(notes: notes);

  /// Saves the purchase and returns its number.
  Future<int> save() async {
    _saving = true;
    notifyListeners();
    try {
      return await _purchases.create(_draft);
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
