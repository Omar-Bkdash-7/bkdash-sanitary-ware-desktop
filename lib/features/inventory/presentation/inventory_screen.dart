import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/core/widgets/stat_tile.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/inventory/presentation/inventory_controller.dart';
import 'package:bkdash_sanitary_ware/features/inventory/presentation/item_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The stock list: categories, totals, search and the add / edit / delete of items.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InventoryController>();
    return Scaffold(
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => _InventoryBody(controller: controller),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showItemFormSheet(context, controller: controller),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة صنف'),
      ),
    );
  }
}

class _InventoryBody extends StatelessWidget {
  const _InventoryBody({required this.controller});

  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.visibleItems;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SearchField(
            hint: 'ابحث بالاسم أو الرمز...',
            onChanged: controller.setQuery,
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _CategoryChip(
                label: AppStrings.all,
                selected: controller.selectedCategory == null,
                onSelected: () => controller.selectCategory(null),
              ),
              for (final category in controller.categories)
                _CategoryChip(
                  label: category,
                  selected: controller.selectedCategory == category,
                  onSelected: () => controller.selectCategory(category),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _StatsCard(stats: controller.stats),
        ),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: controller.items.isEmpty
                      ? 'لا توجد أصناف بعد'
                      : 'لا توجد نتائج مطابقة',
                  message: controller.items.isEmpty
                      ? 'اضغط «إضافة صنف» لتسجيل أول مادة.'
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ItemCard(
                    item: items[index],
                    onEdit: () => showItemFormSheet(
                      context,
                      controller: controller,
                      item: items[index],
                    ),
                    onDelete: () => _confirmDelete(context, items[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, Item item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف الصنف',
      message: 'هل تريد حذف "${item.name}"؟ ستبقى الفواتير القديمة كما هي.',
      confirmLabel: AppStrings.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runUiAction(
      context,
      () => controller.deleteItem(item.id),
      successMessage: 'تم حذف الصنف',
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final InventoryStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'الأصناف / القطع',
                icon: Icons.category_outlined,
                value: Text('${stats.kinds} / ${stats.pieces}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'قيمة التكلفة',
                icon: Icons.payments_outlined,
                color: scheme.info,
                value: MoneyText(stats.costValue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'قيمة البيع',
                icon: Icons.sell_outlined,
                color: scheme.warning,
                value: MoneyText(stats.saleValue),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'الربح المتوقع',
                icon: Icons.trending_up_rounded,
                color: scheme.success,
                value: MoneyText(stats.expectedProfit),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final Item item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.sku}  •  ${item.unit}',
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      children: [
                        _PriceLabel(label: 'تكلفة', amount: item.cost),
                        _PriceLabel(
                          label: 'بيع',
                          amount: item.price,
                          color: scheme.primary,
                          bold: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  _QuantityBadge(item: item),
                  PopupMenuButton<String>(
                    tooltip: '',
                    onSelected: (value) =>
                        value == 'delete' ? onDelete() : onEdit(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(AppStrings.edit),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(AppStrings.delete),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceLabel extends StatelessWidget {
  const _PriceLabel({
    required this.label,
    required this.amount,
    this.color,
    this.bold = false,
  });

  final String label;
  final Money amount;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        MoneyText(
          amount,
          color: color,
          fontWeight: bold ? FontWeight.bold : null,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color color;
    final String text;
    if (item.isOutOfStock) {
      color = scheme.error;
      text = 'نفد';
    } else if (item.isLowStock) {
      color = scheme.warning;
      text = '${item.quantity}';
    } else {
      color = scheme.success;
      text = '${item.quantity}';
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            item.isLowStock ? 'منخفض' : 'الكمية',
            style: TextStyle(color: color, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
