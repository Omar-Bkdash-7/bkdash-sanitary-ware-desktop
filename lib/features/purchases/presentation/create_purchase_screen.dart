import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/integer_form_field.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_form_field.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase_draft.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/create_purchase_controller.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/new_purchase_item_sheet.dart';
import 'package:bkdash_sanitary_ware/features/purchases/presentation/purchase_item_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Buys pieces from [customer] into the stock.
///
/// Closes with the purchase number when it was saved.
class CreatePurchaseScreen extends StatelessWidget {
  const CreatePurchaseScreen({super.key, required this.customer});

  /// The seller; purchases are always tied to a registered customer because
  /// the money may be owed to him later.
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CreatePurchaseController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return CreatePurchaseController(
          items: deps.items,
          customers: deps.customers,
          purchases: deps.purchases,
          customer: customer,
        )..load();
      },
      child: const _CreatePurchaseView(),
    );
  }
}

class _CreatePurchaseView extends StatefulWidget {
  const _CreatePurchaseView();

  @override
  State<_CreatePurchaseView> createState() => _CreatePurchaseViewState();
}

class _CreatePurchaseViewState extends State<_CreatePurchaseView> {
  final TextEditingController _paidNow = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// Fills the text fields once, after the customer was loaded.
  bool _bound = false;

  @override
  void dispose() {
    _paidNow.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(CreatePurchaseController controller) async {
    final navigator = Navigator.of(context);
    try {
      final id = await controller.save();
      navigator.pop(id);
    } on AppException catch (error) {
      if (mounted) showAppSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showConfirmDialog(
      context,
      title: 'تجاهل عملية الشراء؟',
      message: 'ستفقد الأصناف التي أضفتها إلى عملية الشراء.',
      confirmLabel: 'تجاهل',
      destructive: true,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CreatePurchaseController>();
    final draft = controller.draft;
    if (!_bound && controller.status == LoadStatus.ready) {
      // An empty field means "nothing paid now"; the draft uses zero.
      _paidNow.text = draft.paidNow.isPositive
          ? draft.paidNow.toInputString()
          : '';
      _notes.text = draft.notes;
      _bound = true;
    }
    return PopScope(
      canPop: draft.lines.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('شراء من الزبون')),
        body: LoadStateView(
          status: controller.status,
          errorMessage: controller.errorMessage,
          onRetry: controller.load,
          builder: (context) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _CustomerSection(controller: controller),
              const SizedBox(height: 12),
              _LinesSection(controller: controller),
              const SizedBox(height: 12),
              _PaymentSection(controller: controller, paidNow: _paidNow),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                onChanged: controller.setNotes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        bottomNavigationBar: _SummaryBar(
          draft: draft,
          saving: controller.isSaving,
          onSave: () => _save(controller),
        ),
      ),
    );
  }
}

class _CustomerSection extends StatelessWidget {
  const _CustomerSection({required this.controller});

  final CreatePurchaseController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final customer = controller.customer;
    final summary = controller.summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text(customer.name.characters.first),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (customer.phone.isNotEmpty)
                    Text(
                      customer.phone,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (summary != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      summary.weOwe
                          ? 'المستحق له حالياً: ${summary.amountPayable.format()}'
                          : summary.customerOwes
                          ? 'عليه حالياً: ${summary.amountDue.format()}'
                          : 'حسابه خالص',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: summary.weOwe
                            ? scheme.primary
                            : summary.customerOwes
                            ? scheme.error
                            : scheme.success,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinesSection extends StatelessWidget {
  const _LinesSection({required this.controller});

  final CreatePurchaseController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = controller.draft.lines;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الأصناف المشتراة', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      showPurchaseItemPickerSheet(context, controller),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة من المخزون'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      showNewPurchaseItemSheet(context, controller),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('صنف جديد'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'لم تُضف أصنافاً بعد',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                _PurchaseLineTile(
                  line: lines[i],
                  onDecrease: () => _attempt(
                    context,
                    () => controller.setLineQuantity(i, lines[i].quantity - 1),
                  ),
                  onIncrease: () => _attempt(
                    context,
                    () => controller.setLineQuantity(i, lines[i].quantity + 1),
                  ),
                  onEdit: () => _editLine(context, i),
                  onRemove: () => controller.removeLine(i),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _editLine(BuildContext context, int index) {
    final line = controller.draft.lines[index];
    return showDialog<void>(
      context: context,
      builder: (_) => _PurchaseLineEditDialog(
        line: line,
        onSave: (quantity, unitCost, salePrice) {
          _attempt(context, () {
            controller
              ..setLineQuantity(index, quantity)
              ..setLineUnitCost(index, unitCost);
            if (line.isNewItem) controller.setLineSalePrice(index, salePrice);
          });
        },
      ),
    );
  }
}

class _PurchaseLineTile extends StatelessWidget {
  const _PurchaseLineTile({
    required this.line,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEdit,
    required this.onRemove,
  });

  final PurchaseLine line;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      line.itemName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (line.isNewItem) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'جديد',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'حذف السطر',
              icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              onPressed: onRemove,
            ),
          ],
        ),
        Row(
          children: [
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoneyText(line.unitCost, style: theme.textTheme.bodyMedium),
                    Text(' / ${line.unit}', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, size: 14, color: scheme.primary),
                  ],
                ),
              ),
            ),
            const Spacer(),
            IconButton.outlined(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_rounded),
              onPressed: line.quantity > 1 ? onDecrease : null,
            ),
            InkWell(
              onTap: onEdit,
              child: SizedBox(
                width: 40,
                child: Center(
                  child: Text(
                    '${line.quantity}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton.outlined(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded),
              onPressed: onIncrease,
            ),
          ],
        ),
        Row(
          children: [
            if (line.isNewItem)
              Text(
                'سيُباع بـ ${line.salePrice.format()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const Spacer(),
            MoneyText(
              line.lineTotal,
              fontWeight: FontWeight.bold,
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({required this.controller, required this.paidNow});

  final CreatePurchaseController controller;
  final TextEditingController paidNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الدفع للزبون', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            MoneyFormField(
              controller: paidNow,
              label: 'المبلغ المدفوع الآن (اختياري)',
              required: false,
              onChanged: (value) =>
                  controller.setPaidNow(Money.tryParse(value) ?? Money.zero),
            ),
            const SizedBox(height: 8),
            Text(
              'إذا دفعت للزبون مبلغاً الآن فسجّله هنا. الباقي يبقى مستحقاً له '
              'ويمكن دفعه لاحقاً من حسابه.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseLineEditDialog extends StatefulWidget {
  const _PurchaseLineEditDialog({required this.line, required this.onSave});

  final PurchaseLine line;
  final void Function(int quantity, Money unitCost, Money salePrice) onSave;

  @override
  State<_PurchaseLineEditDialog> createState() =>
      _PurchaseLineEditDialogState();
}

class _PurchaseLineEditDialogState extends State<_PurchaseLineEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _unitCost;
  late final TextEditingController _salePrice;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(text: '${widget.line.quantity}');
    _unitCost = TextEditingController(
      text: widget.line.unitCost.toInputString(),
    );
    _salePrice = TextEditingController(
      text: widget.line.salePrice.toInputString(),
    );
  }

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _salePrice.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(
      tryParseInt(_quantity.text)!,
      Money.tryParse(_unitCost.text)!,
      widget.line.isNewItem
          ? Money.tryParse(_salePrice.text)!
          : widget.line.salePrice,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.line.itemName),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IntegerFormField(
              controller: _quantity,
              label: 'الكمية المشتراة',
              min: 1,
            ),
            const SizedBox(height: 12),
            MoneyFormField(controller: _unitCost, label: 'سعر الشراء للوحدة'),
            if (widget.line.isNewItem) ...[
              const SizedBox(height: 12),
              MoneyFormField(
                controller: _salePrice,
                label: 'سعر البيع في المخزون',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(onPressed: _save, child: const Text(AppStrings.save)),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.draft,
    required this.saving,
    required this.onSave,
  });

  final PurchaseDraft draft;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryRow(label: 'الإجمالي', amount: draft.total, bold: true),
              _SummaryRow(
                label: 'المدفوع الآن',
                amount: draft.paidNow,
                color: scheme.success,
              ),
              _SummaryRow(
                label: 'المتبقي للزبون',
                amount: draft.remaining,
                color: draft.remaining.isPositive ? scheme.primary : null,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving || draft.lines.isEmpty ? null : onSave,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('حفظ عملية الشراء'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          MoneyText(
            amount,
            color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            style: bold ? Theme.of(context).textTheme.titleMedium : null,
          ),
        ],
      ),
    );
  }
}

/// Runs [action]; a refusal is shown as a message.
void _attempt(BuildContext context, void Function() action) {
  try {
    action();
  } on AppException catch (error) {
    showAppSnackBar(context, error.message, isError: true);
  }
}
