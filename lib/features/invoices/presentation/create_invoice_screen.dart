import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice_draft.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/create_invoice_controller.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/customer_picker_sheet.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/item_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Writes a new invoice, or rewrites the saved one when [invoiceId] is given.
/// Closes with the invoice number when it was saved.
class CreateInvoiceScreen extends StatelessWidget {
  const CreateInvoiceScreen({super.key, this.invoiceId});

  /// The invoice being edited; `null` for a new one.
  final int? invoiceId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CreateInvoiceController>(
      create: (context) {
        final deps = context.read<AppDependencies>();
        return CreateInvoiceController(
          items: deps.items,
          customers: deps.customers,
          invoices: deps.invoices,
          sync: deps.sync,
          invoiceId: invoiceId,
        )..load();
      },
      child: _CreateInvoiceView(invoiceId: invoiceId),
    );
  }
}

class _CreateInvoiceView extends StatefulWidget {
  const _CreateInvoiceView({this.invoiceId});

  final int? invoiceId;

  @override
  State<_CreateInvoiceView> createState() => _CreateInvoiceViewState();
}

class _CreateInvoiceViewState extends State<_CreateInvoiceView> {
  final TextEditingController _partialPaid = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// Fills the text fields from the saved invoice once, after it was loaded.
  bool _bound = false;

  bool get _isEditing => widget.invoiceId != null;

  @override
  void dispose() {
    _partialPaid.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(CreateInvoiceController controller) async {
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
      title: _isEditing ? 'إلغاء التعديل؟' : 'تجاهل الفاتورة؟',
      message: _isEditing
          ? 'ستبقى الفاتورة كما كانت قبل التعديل.'
          : 'ستفقد الأصناف التي أضفتها إلى هذه الفاتورة.',
      confirmLabel: _isEditing ? 'إلغاء التعديل' : 'تجاهل',
      destructive: true,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CreateInvoiceController>();
    final draft = controller.draft;
    if (!_bound && controller.status == LoadStatus.ready) {
      _partialPaid.text = controller.draft.partialPaid.toInputString();
      _notes.text = controller.draft.notes;
      _bound = true;
    }
    return PopScope(
      canPop: draft.lines.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing ? 'تعديل الفاتورة #${widget.invoiceId}' : 'فاتورة جديدة',
          ),
        ),
        body: LoadStateView(
          status: controller.status,
          errorMessage: controller.errorMessage,
          onRetry: controller.load,
          builder: (context) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _CustomerSection(controller: controller),
              const SizedBox(height: 12),
              _PaymentSection(
                controller: controller,
                partialPaid: _partialPaid,
              ),
              const SizedBox(height: 12),
              _LinesSection(controller: controller),
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
          isEditing: _isEditing,
          onSave: () => _save(controller),
        ),
      ),
    );
  }
}

/// Runs [action]; a refusal such as "not enough stock" is shown as a message.
void _attempt(BuildContext context, void Function() action) {
  try {
    action();
  } on AppException catch (error) {
    showAppSnackBar(context, error.message, isError: true);
  }
}

class _CustomerSection extends StatelessWidget {
  const _CustomerSection({required this.controller});

  final CreateInvoiceController controller;

  @override
  Widget build(BuildContext context) {
    final customer = controller.draft.customer;
    return Card(
      child: ListTile(
        onTap: () => showCustomerPickerSheet(context, controller),
        leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
        title: Text(customer?.name ?? 'زبون نقدي (بدون تسجيل)'),
        subtitle: Text(
          customer == null
              ? 'اختر زبوناً إذا كان البيع آجلاً أو بدفعة جزئية'
              : (customer.phone.isEmpty ? 'بدون رقم هاتف' : customer.phone),
          textDirection: customer == null || customer.phone.isEmpty
              ? null
              : TextDirection.ltr,
        ),
        trailing: customer == null
            ? const Icon(Icons.chevron_left_rounded)
            : IconButton(
                tooltip: 'إلغاء اختيار الزبون',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => controller.selectCustomer(null),
              ),
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({required this.controller, required this.partialPaid});

  final CreateInvoiceController controller;
  final TextEditingController partialPaid;

  static String _hint(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'يُسدَّد المبلغ كاملاً الآن.',
    PaymentMethod.credit => 'يُسجَّل كامل المبلغ ذمةً على الزبون.',
    PaymentMethod.partial => 'يُسجَّل الباقي ذمةً على الزبون.',
    PaymentMethod.transfer => 'يُسدَّد المبلغ كاملاً بالحوالة.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = controller.draft;
    final method = draft.paymentMethod;
    final missingCustomer = method.needsCustomer && draft.customer == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طريقة الدفع', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in PaymentMethod.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: option == method,
                    onSelected: (_) => controller.setPaymentMethod(option),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _hint(method),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (method == PaymentMethod.partial) ...[
              const SizedBox(height: 12),
              MoneyFormField(
                controller: partialPaid,
                label: 'المبلغ المدفوع الآن',
                onChanged: (value) => controller.setPartialPaid(
                  Money.tryParse(value) ?? Money.zero,
                ),
              ),
            ],
            if (missingCustomer) ...[
              const SizedBox(height: 8),
              Text(
                'اختر زبوناً مسجّلاً لهذه الطريقة.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinesSection extends StatelessWidget {
  const _LinesSection({required this.controller});

  final CreateInvoiceController controller;

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
            Row(
              children: [
                Expanded(
                  child: Text('الأصناف', style: theme.textTheme.titleMedium),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showItemPickerSheet(context, controller),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة صنف'),
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
                _DraftLineTile(
                  line: lines[i],
                  onDecrease: () => _attempt(
                    context,
                    () => controller.setLineQuantity(i, lines[i].quantity - 1),
                  ),
                  onIncrease: () => _attempt(
                    context,
                    () => controller.setLineQuantity(i, lines[i].quantity + 1),
                  ),
                  onEdit: () => _editLine(context, controller, i),
                  onRemove: () => controller.removeLine(i),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _editLine(
    BuildContext context,
    CreateInvoiceController controller,
    int index,
  ) {
    final line = controller.draft.lines[index];
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _LineEditDialog(
        line: line,
        onSave: (quantity, price) {
          _attempt(context, () {
            controller
              ..setLineQuantity(index, quantity)
              ..setLineUnitPrice(index, price);
          });
        },
      ),
    );
  }
}

class _DraftLineTile extends StatelessWidget {
  const _DraftLineTile({
    required this.line,
    required this.onDecrease,
    required this.onIncrease,
    required this.onEdit,
    required this.onRemove,
  });

  final InvoiceLine line;
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
              child: Text(
                line.itemName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
                    MoneyText(
                      line.unitPrice,
                      style: theme.textTheme.bodyMedium,
                    ),
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
              onPressed: line.quantity < line.available ? onIncrease : null,
            ),
          ],
        ),
        Row(
          children: [
            if (line.unitPrice < line.unitCost)
              Text(
                'السعر أقل من التكلفة',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.warning,
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

class _LineEditDialog extends StatefulWidget {
  const _LineEditDialog({required this.line, required this.onSave});

  final InvoiceLine line;
  final void Function(int quantity, Money price) onSave;

  @override
  State<_LineEditDialog> createState() => _LineEditDialogState();
}

class _LineEditDialogState extends State<_LineEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(text: '${widget.line.quantity}');
    _price = TextEditingController(text: widget.line.unitPrice.toInputString());
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(tryParseInt(_quantity.text)!, Money.tryParse(_price.text)!);
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
              label: 'الكمية (المتوفر: ${widget.line.available})',
              min: 1,
            ),
            const SizedBox(height: 12),
            MoneyFormField(controller: _price, label: 'سعر الوحدة'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.draft,
    required this.saving,
    required this.onSave,
    this.isEditing = false,
  });

  final InvoiceDraft draft;
  final bool saving;
  final bool isEditing;
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
                label: 'المدفوع',
                amount: draft.paid,
                color: scheme.success,
              ),
              _SummaryRow(
                label: 'المتبقي (ذمة)',
                amount: draft.remaining,
                color: draft.remaining.isPositive ? scheme.error : null,
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
                  label: Text(isEditing ? 'حفظ التعديلات' : 'حفظ الفاتورة'),
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
