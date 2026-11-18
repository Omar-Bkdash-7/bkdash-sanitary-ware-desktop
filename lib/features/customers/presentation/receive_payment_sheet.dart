import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:flutter/material.dart';

/// Records a payment against a customer's debt. Closes with `true` on success.
///
/// [onSubmit] stores the payment; an [AppException] it throws is shown inside
/// the sheet.
Future<bool?> showReceivePaymentSheet(
  BuildContext context, {
  required String customerName,
  required Money debt,
  required Future<void> Function(Money amount, String note) onSubmit,
}) {
  return showFormSheet<bool>(
    context,
    builder: (_) => _ReceivePaymentForm(
      customerName: customerName,
      debt: debt,
      onSubmit: onSubmit,
    ),
  );
}

class _ReceivePaymentForm extends StatefulWidget {
  const _ReceivePaymentForm({
    required this.customerName,
    required this.debt,
    required this.onSubmit,
  });

  final String customerName;
  final Money debt;
  final Future<void> Function(Money amount, String note) onSubmit;

  @override
  State<_ReceivePaymentForm> createState() => _ReceivePaymentFormState();
}

class _ReceivePaymentFormState extends State<_ReceivePaymentForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.requiredField;
    final amount = Money.tryParse(value);
    if (amount == null) return AppStrings.invalidAmount;
    if (!amount.isPositive) return AppStrings.amountMustBePositive;
    if (amount > widget.debt) {
      return 'المبلغ أكبر من الدين (${widget.debt.format()})';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(Money.tryParse(_amount.text)!, _note.text);
      navigator.pop(true);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تسديد دفعة', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.customerName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الدين الحالي'),
                  MoneyText(
                    widget.debt,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'المبلغ المدفوع',
                prefixText: r'$',
                suffixIcon: TextButton(
                  onPressed: () => setState(
                    () => _amount.text = widget.debt.toInputString(),
                  ),
                  child: const Text('كامل الدين'),
                ),
              ),
              validator: _validateAmount,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
            const SizedBox(height: 6),
            Text(
              'تُوزَّع الدفعة على أقدم الفواتير غير المسددة أولاً.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? AppStrings.loading : 'تسجيل الدفعة'),
            ),
          ],
        ),
      ),
    );
  }
}
