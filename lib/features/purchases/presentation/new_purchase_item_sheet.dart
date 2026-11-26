import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_draft.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/create_purchase_controller.dart';
import 'package:flutter/material.dart';

/// Asks for the data of a product that is not in the stock, then adds it to
/// the purchase (it is created in the inventory when the purchase is saved).
Future<void> showNewPurchaseItemSheet(
  BuildContext context,
  CreatePurchaseController controller,
) {
  return showFormSheet<void>(
    context,
    builder: (_) => _NewPurchaseItemForm(controller: controller),
  );
}

class _NewPurchaseItemForm extends StatefulWidget {
  const _NewPurchaseItemForm({required this.controller});

  final CreatePurchaseController controller;

  @override
  State<_NewPurchaseItemForm> createState() => _NewPurchaseItemFormState();
}

class _NewPurchaseItemFormState extends State<_NewPurchaseItemForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _sku = TextEditingController();
  final TextEditingController _unit = TextEditingController(
    text: AppStrings.piece,
  );
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _unitCost = TextEditingController();
  final TextEditingController _salePrice = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _category,
      _sku,
      _unit,
      _quantity,
      _unitCost,
      _salePrice,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    try {
      widget.controller.addNewItem(
        PurchaseLine.newItem(
          itemName: _name.text,
          category: _category.text,
          sku: _sku.text,
          unit: _unit.text,
          quantity: tryParseInt(_quantity.text)!,
          unitCost: Money.tryParse(_unitCost.text)!,
          salePrice: Money.tryParse(_salePrice.text)!,
        ),
      );
      Navigator.of(context).pop();
    } on AppException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('صنف جديد', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'سيُضاف هذا الصنف إلى المخزون عند حفظ عملية الشراء.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'اسم الصنف'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? AppStrings.requiredField
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _category,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'الفئة'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? AppStrings.requiredField
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sku,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'الرمز (اختياري)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: IntegerFormField(
                    controller: _quantity,
                    label: 'الكمية المشتراة',
                    min: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MoneyFormField(
                    controller: _unitCost,
                    label: 'سعر الشراء للوحدة',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MoneyFormField(
              controller: _salePrice,
              label: 'سعر البيع في المخزون',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة إلى عملية الشراء'),
            ),
          ],
        ),
      ),
    );
  }
}
