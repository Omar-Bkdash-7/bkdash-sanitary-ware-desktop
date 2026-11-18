import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/create_invoice_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Lets the user add products to the invoice; the sheet stays open so several
/// products can be added in a row.
Future<void> showItemPickerSheet(
  BuildContext context,
  CreateInvoiceController controller,
) {
  return showFormSheet<void>(
    context,
    builder: (_) => ChangeNotifierProvider<CreateInvoiceController>.value(
      value: controller,
      child: const _ItemPicker(),
    ),
  );
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker();

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _query = '';

  void _add(CreateInvoiceController controller, Item item) {
    try {
      controller.addItem(item);
    } on AppException catch (error) {
      showAppSnackBar(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CreateInvoiceController>();
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
            child: SearchField(
              hint: 'ابحث بالاسم أو الرمز أو الفئة...',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'لا توجد أصناف مطابقة',
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final inInvoice = controller.draft.lines
                          .where((line) => line.itemId == item.id)
                          .fold(0, (sum, line) => sum + line.quantity);
                      final left = item.quantity - inInvoice;
                      return ListTile(
                        enabled: left > 0,
                        onTap: left > 0 ? () => _add(controller, item) : null,
                        title: Text(item.name),
                        subtitle: Row(
                          children: [
                            MoneyText(item.price),
                            Text(
                              item.isOutOfStock
                                  ? '  •  نفد من المخزون'
                                  : '  •  المتوفر: $left ${item.unit}',
                              style: TextStyle(
                                color: item.isOutOfStock
                                    ? theme.colorScheme.error
                                    : (item.isLowStock
                                          ? theme.colorScheme.warning
                                          : null),
                              ),
                            ),
                          ],
                        ),
                        trailing: inInvoice > 0
                            ? CircleAvatar(
                                radius: 14,
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                child: Text(
                                  '$inInvoice',
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
