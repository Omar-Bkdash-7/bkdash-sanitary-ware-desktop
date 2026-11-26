import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';

/// A product line of a purchase that is still being written.
///
/// An existing inventory item has an [itemId]. A new item has `null` and is
/// created in the stock when the purchase is saved; [salePrice] is then used
/// for its price in the inventory.
final class PurchaseLine {
  const PurchaseLine({
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.sku,
    this.container = 0,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.salePrice,
  });

  factory PurchaseLine.fromItem(
    Item item, {
    int quantity = 1,
    Money? unitCost,
  }) => PurchaseLine(
    itemId: item.id,
    itemName: item.name,
    category: item.category,
    sku: item.sku,
    container: item.container,
    unit: item.unit,
    quantity: quantity,
    unitCost: unitCost ?? item.cost,
    salePrice: item.price,
  );

  factory PurchaseLine.newItem({
    required String itemName,
    required String category,
    required String sku,
    int container = 0,
    required String unit,
    required int quantity,
    required Money unitCost,
    required Money salePrice,
  }) => PurchaseLine(
    itemId: null,
    itemName: itemName.trim(),
    category: category.trim(),
    sku: sku.trim(),
    container: container,
    unit: unit.trim(),
    quantity: quantity,
    unitCost: unitCost,
    salePrice: salePrice,
  );

  /// `null` when the purchase creates a new inventory item.
  final int? itemId;
  final String itemName;
  final String category;
  final String sku;

  /// The container the pieces came from (`0` when not from one).
  final int container;

  final String unit;
  final int quantity;

  /// What the shop pays the customer for one piece.
  final Money unitCost;

  /// The sale price used only when a new inventory item is created.
  final Money salePrice;

  bool get isNewItem => itemId == null;

  Money get lineTotal => unitCost * quantity;

  PurchaseLine copyWith({
    int? quantity,
    Money? unitCost,
    Money? salePrice,
    String? itemName,
    String? category,
    String? sku,
    int? container,
    String? unit,
  }) => PurchaseLine(
    itemId: itemId,
    itemName: itemName ?? this.itemName,
    category: category ?? this.category,
    sku: sku ?? this.sku,
    container: container ?? this.container,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    unitCost: unitCost ?? this.unitCost,
    salePrice: salePrice ?? this.salePrice,
  );
}

/// A purchase being written: pure data and rules, no database.
final class PurchaseDraft {
  const PurchaseDraft({
    required this.customer,
    this.lines = const <PurchaseLine>[],
    this.paidNow = Money.zero,
    this.notes = '',
  });

  final Customer customer;
  final List<PurchaseLine> lines;

  /// Paid to the customer when the purchase is saved; the rest stays owed.
  final Money paidNow;
  final String notes;

  Money get total => Money.sum(lines.map((line) => line.lineTotal));

  Money get remaining => total - paidNow;

  int get pieces => lines.fold(0, (sum, line) => sum + line.quantity);

  PurchaseDraft copyWith({
    List<PurchaseLine>? lines,
    Money? paidNow,
    String? notes,
  }) => PurchaseDraft(
    customer: customer,
    lines: lines ?? this.lines,
    paidNow: paidNow ?? this.paidNow,
    notes: notes ?? this.notes,
  );

  /// Adds [item]; buying the same existing item twice adds to its line.
  PurchaseDraft addItem(Item item, {int quantity = 1, Money? unitCost}) {
    final index = lines.indexWhere((line) => line.itemId == item.id);
    if (index == -1) {
      return copyWith(
        lines: [
          ...lines,
          PurchaseLine.fromItem(item, quantity: quantity, unitCost: unitCost),
        ],
      );
    }
    final merged = lines[index].copyWith(
      quantity: lines[index].quantity + quantity,
    );
    return copyWith(lines: [...lines]..[index] = merged);
  }

  /// Adds a line for a product that is not in the stock yet.
  PurchaseDraft addNewItem(PurchaseLine line) =>
      copyWith(lines: [...lines, line]);

  PurchaseDraft updateLine(
    int index, {
    int? quantity,
    Money? unitCost,
    Money? salePrice,
  }) {
    final updated = lines[index].copyWith(
      quantity: quantity,
      unitCost: unitCost,
      salePrice: salePrice,
    );
    return copyWith(lines: [...lines]..[index] = updated);
  }

  PurchaseDraft removeLine(int index) =>
      copyWith(lines: [...lines]..removeAt(index));

  /// Throws a [ValidationException] when the purchase cannot be saved.
  void validate() {
    if (lines.isEmpty) {
      throw const ValidationException(
        'أضف صنفاً واحداً على الأقل إلى عملية الشراء.',
      );
    }
    final itemIds = <int>{};
    final newSkus = <String>{};
    for (final line in lines) {
      if (line.quantity < 1) {
        throw ValidationException(
          'كمية السطر "${line.itemName}" يجب أن تكون 1 على الأقل.',
        );
      }
      if (line.unitCost.isNegative) {
        throw ValidationException('تكلفة السطر "${line.itemName}" غير صحيحة.');
      }
      if (line.itemName.trim().isEmpty || line.category.trim().isEmpty) {
        throw const ValidationException('اسم الصنف وفئته مطلوبان في كل سطر.');
      }
      if (line.isNewItem) {
        if (line.salePrice.isNegative) {
          throw ValidationException(
            'سعر بيع الصنف "${line.itemName}" غير صحيح.',
          );
        }
        final sku = line.sku.trim().toLowerCase();
        if (sku.isNotEmpty && !newSkus.add(sku)) {
          throw ValidationException('الرمز "$sku" مكرر في عملية الشراء.');
        }
      } else if (!itemIds.add(line.itemId!)) {
        throw ValidationException(
          'الصنف "${line.itemName}" مكرر في عملية الشراء.',
        );
      }
    }
    if (paidNow.isNegative) {
      throw const ValidationException(AppStrings.invalidAmount);
    }
    if (paidNow > total) {
      throw const ValidationException(
        'المبلغ المدفوع للزبون أكبر من إجمالي عملية الشراء.',
      );
    }
  }
}
