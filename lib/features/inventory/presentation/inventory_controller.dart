import 'dart:async';

import 'package:bkdash_sanitary_ware/core/events/data_change_notifier.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/features/inventory/data/item_repository.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';

/// Totals shown at the top of the inventory screen.
final class InventoryStats {
  const InventoryStats({
    required this.kinds,
    required this.pieces,
    required this.costValue,
    required this.saleValue,
  });

  factory InventoryStats.of(Iterable<Item> items) => InventoryStats(
    kinds: items.length,
    pieces: items.fold(0, (total, item) => total + item.quantity),
    costValue: Money.sum(items.map((item) => item.stockCostValue)),
    saleValue: Money.sum(items.map((item) => item.stockSaleValue)),
  );

  final int kinds;
  final int pieces;
  final Money costValue;
  final Money saleValue;

  Money get expectedProfit => saleValue - costValue;
}

class InventoryController extends BaseController {
  InventoryController({
    required ItemRepository repository,
    required DataChangeNotifier changes,
  }) : _repository = repository,
       _changes = changes {
    _changes.addListener(_onDataChanged);
  }

  final ItemRepository _repository;
  final DataChangeNotifier _changes;

  List<Item> _items = const <Item>[];
  String? _selectedCategory;
  String _query = '';

  List<Item> get items => _items;

  /// `null` means "all categories".
  String? get selectedCategory => _selectedCategory;

  List<String> get categories =>
      (<String>{for (final item in _items) item.category}.toList()..sort());

  /// Items of the selected category that match the search text.
  List<Item> get visibleItems {
    final query = normalizeForSearch(_query);
    return _items.where((item) {
      if (_selectedCategory != null && item.category != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return normalizeForSearch(item.name).contains(query) ||
          normalizeForSearch(item.sku).contains(query) ||
          normalizeForSearch(item.notes).contains(query);
    }).toList();
  }

  /// Totals of the selected category (or of everything).
  InventoryStats get stats => InventoryStats.of(
    _selectedCategory == null
        ? _items
        : _items.where((item) => item.category == _selectedCategory),
  );

  Future<void> load() => runLoad(() async {
    _items = await _repository.getAll();
    if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
      _selectedCategory = null;
    }
  });

  void selectCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  Future<void> addItem(ItemInput input) async {
    final created = await _repository.create(input);
    _selectedCategory = created.category;
  }

  Future<void> updateItem(int id, ItemInput input) =>
      _repository.update(id, input);

  Future<void> deleteItem(int id) => _repository.delete(id);

  void _onDataChanged() => unawaited(load());

  @override
  void dispose() {
    _changes.removeListener(_onDataChanged);
    super.dispose();
  }
}
