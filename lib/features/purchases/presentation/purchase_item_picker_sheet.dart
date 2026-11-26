import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/create_purchase_controller.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/new_purchase_item_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Lets the user add products to the purchase; the sheet stays open so several
/// products can be added in a row.
Future<void> showPurchaseItemPickerSheet(
  BuildContext context,
  CreatePurchaseController controller,
) {
  return showFormSheet<void>(
    context,
    builder: (_) => ChangeNotifierProvider<CreatePurchaseController>.value(
      value: controller,
      child: const _PurchaseItemPicker(),
    ),
  );
}

class _PurchaseItemPicker extends StatefulWidget {
  const _PurchaseItemPicker();

  @override
  State<_PurchaseItemPicker> createState() => _PurchaseItemPickerState();
}

class _PurchaseItemPickerState extends State<_PurchaseItemPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CreatePurchaseController>();
    final theme = Theme.of(context);
    final query = normalizeForSearch(_query);
    final items = controller.catalog.where((item) {
      if (query.isEmpty) return true;
      return normalizeForSearch(item.name).contains(query) ||
          normalizeForSearch(item.sku).contains(query) ||
          normalizeForSearch(item.category).contains(query);
    }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('إضافة أصناف', style: theme.textTheme.titleLarge),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('تم'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => showNewPurchaseItemSheet(context, controller),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('صنف جديد غير موجود في المخزون'),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchField(
              hint: 'ابحث بالاسم أو الرمز أو الفئة...',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: controller.catalog.isEmpty
                        ? 'المخزون فارغ'
                        : 'لا توجد أصناف مطابقة',
                    message: controller.catalog.isEmpty
                        ? 'استخدم زر "صنف جديد" لإضافة أول صنف.'
                        : null,
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final inPurchase = controller.draft.lines
                          .where((line) => line.itemId == item.id)
                          .fold(0, (sum, line) => sum + line.quantity);
                      return ListTile(
                        onTap: () => controller.addItem(item),
                        title: Text(item.name),
                        subtitle: Row(
                          children: [
                            Text('التكلفة: '),
                            MoneyText(item.cost),
                            Text(
                              '  •  المتوفر: ${item.quantity} ${item.unit}',
                              style: TextStyle(
                                color: item.isLowStock
                                    ? theme.colorScheme.warning
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        trailing: inPurchase > 0
                            ? CircleAvatar(
                                radius: 14,
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                child: Text(
                                  '$inPurchase',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )
                            : const Icon(Icons.add_circle_outline_rounded),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
