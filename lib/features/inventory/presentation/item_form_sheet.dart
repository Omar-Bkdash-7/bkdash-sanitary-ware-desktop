import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/formatting/validators.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/integer_form_field.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_form_field.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter/material.dart';

/// Opens the add / edit item form ([item] is `null` when adding).
Future<void> showItemFormSheet(
  BuildContext context, {
  required InventoryController controller,
  Item? item,
}) {
  return showFormSheet<void>(
    context,
    builder: (_) => ItemFormSheet(controller: controller, item: item),
  );
}

class ItemFormSheet extends StatefulWidget {
  const ItemFormSheet({super.key, required this.controller, this.item});

  final InventoryController controller;
  final Item? item;

  @override
  State<ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<ItemFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _category;
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _unit;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  late final TextEditingController _notes;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _category = TextEditingController(
      text: item?.category ?? widget.controller.selectedCategory ?? '',
    );
    _name = TextEditingController(text: item?.name ?? '');
    _sku = TextEditingController(text: item?.sku ?? '');
    _unit = TextEditingController(text: item?.unit ?? AppStrings.piece);
    _cost = TextEditingController(text: item?.cost.toInputString() ?? '');
    _price = TextEditingController(text: item?.price.toInputString() ?? '');
    _quantity = TextEditingController(text: '${item?.quantity ?? 0}');
    _notes = TextEditingController(text: item?.notes ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _category,
      _name,
      _sku,
      _unit,
      _cost,
      _price,
      _quantity,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final input = ItemInput(
      category: _category.text,
      name: _name.text,
      sku: _sku.text,
      unit: _unit.text,
      cost: Money.tryParse(_cost.text)!,
      price: Money.tryParse(_price.text)!,
      quantity: tryParseInt(_quantity.text)!,
      notes: _notes.text,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = widget.item;
      if (item == null) {
        await widget.controller.addItem(input);
      } else {
        await widget.controller.updateItem(item.id, input);
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'تم تعديل الصنف' : 'تمت إضافة الصنف'),
        ),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = widget.controller.categories;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'تعديل صنف' : 'إضافة صنف جديد',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _category,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'الفئة'),
              validator: Validators.requiredText,
            ),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in categories)
                    ActionChip(
                      label: Text(category),
                      onPressed: () =>
                          setState(() => _category.text = category),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'اسم المادة'),
              validator: Validators.requiredText,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sku,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'الرمز (اختياري)',
                      helperText: 'يُولَّد تلقائياً إن تُرك فارغاً',
                      helperMaxLines: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _unit,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MoneyFormField(
                    controller: _cost,
                    label: 'سعر التكلفة',
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MoneyFormField(
                    controller: _price,
                    label: 'سعر البيع',
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            IntegerFormField(
              controller: _quantity,
              label: 'الكمية في المخزون',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? AppStrings.loading : AppStrings.save),
            ),
          ],
        ),
      ),
    );
  }
}
