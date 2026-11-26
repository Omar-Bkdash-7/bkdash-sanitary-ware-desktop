import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';

/// A product kept in stock.
final class Item {
  const Item({
    required this.id,
    required this.category,
    required this.name,
    required this.sku,
    this.container = 0,
    required this.unit,
    required this.cost,
    required this.price,
    required this.quantity,
    required this.notes,
  });

  factory Item.fromRow(Map<String, Object?> row) {
    return Item(
      id: row['id']! as int,
      category: row['category']! as String,
      name: row['name']! as String,
      sku: row['sku']! as String,
      container: (row['container'] as int?) ?? 0,
      unit: row['unit']! as String,
      cost: Money(row['cost_cents']! as int),
      price: Money(row['price_cents']! as int),
      quantity: row['quantity']! as int,
      notes: (row['notes'] as String?) ?? '',
    );
  }

  final int id;
  final String category;
  final String name;
  final String sku;

  /// The import container the pieces came in (`0` when not from one).
  final int container;

  final String unit;

  /// What one piece costs the shop.
  final Money cost;

  /// What one piece is sold for.
  final Money price;

  /// Pieces in stock.
  final int quantity;
  final String notes;

  bool get isOutOfStock => quantity <= 0;

  bool get isLowStock =>
      quantity > 0 && quantity <= AppConstants.lowStockThreshold;

  Money get unitProfit => price - cost;
  Money get stockCostValue => cost * quantity;
  Money get stockSaleValue => price * quantity;
  Money get expectedProfit => stockSaleValue - stockCostValue;
}

/// What the user types in the add / edit item form.
final class ItemInput {
  const ItemInput({
    required this.category,
    required this.name,
    required this.sku,
    this.container = 0,
    required this.unit,
    required this.cost,
    required this.price,
    required this.quantity,
    required this.notes,
  });

  factory ItemInput.fromItem(Item item) => ItemInput(
    category: item.category,
    name: item.name,
    sku: item.sku,
    container: item.container,
    unit: item.unit,
    cost: item.cost,
    price: item.price,
    quantity: item.quantity,
    notes: item.notes,
  );

  final String category;
  final String name;

  /// Empty means "generate a code for me".
  final String sku;

  /// `0` when the pieces are not tied to an import container.
  final int container;

  final String unit;
  final Money cost;
  final Money price;
  final int quantity;
  final String notes;

  /// Throws [ValidationException] when the data cannot be stored.
  void validate() {
    if (name.trim().isEmpty || category.trim().isEmpty) {
      throw const ValidationException(AppStrings.requiredField);
    }
    if (quantity < 0 ||
        container < 0 ||
        cost.isNegative ||
        price.isNegative) {
      throw const ValidationException(AppStrings.invalidNumber);
    }
  }
}
