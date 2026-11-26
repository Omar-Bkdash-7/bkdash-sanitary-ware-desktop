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
  return _showPaymentSheet(
    context,
    title: 'تسديد دفعة',
    customerName: customerName,
    balanceLabel: 'الدين الحالي',
    maxAmount: debt,
    amountLabel: 'المبلغ المدفوع',
    fullAmountLabel: 'كامل الدين',
    hint: 'تُوزَّع الدفعة على أقدم الفواتير غير المسددة أولاً.',
    submitLabel: 'تسجيل الدفعة',
    emphasizePayment: true,
    onSubmit: onSubmit,
  );
}

/// Records money paid to a customer for purchases. Closes with `true` on
/// success.
///
/// [onSubmit] stores the payment; an [AppException] it throws is shown inside
/// the sheet.
Future<bool?> showPayCustomerSheet(
  BuildContext context, {
  required String customerName,
  required Money payable,
  required Future<void> Function(Money amount, String note) onSubmit,
}) {
  return _showPaymentSheet(
    context,
    title: 'الدفع للزبون',
    customerName: customerName,
    balanceLabel: 'المستحق للزبون',
    maxAmount: payable,
    amountLabel: 'المبلغ المدفوع للزبون',
    fullAmountLabel: 'كامل المستحق',
    hint: 'يُوزَّع المبلغ على أقدم عمليات الشراء غير المسددة أولاً.',
    submitLabel: 'تسجيل الدفع',
    emphasizePayment: false,
    onSubmit: onSubmit,
  );
}

Future<bool?> _showPaymentSheet(
  BuildContext context, {
  required String title,
  required String customerName,
  required String balanceLabel,
  required Money maxAmount,
  required String amountLabel,
  required String fullAmountLabel,
  required String hint,
  required String submitLabel,
  required bool emphasizePayment,
  required Future<void> Function(Money amount, String note) onSubmit,
}) {
  return showFormSheet<bool>(
    context,
    builder: (_) => _PaymentForm(
      title: title,
      customerName: customerName,
      balanceLabel: balanceLabel,
      maxAmount: maxAmount,
      amountLabel: amountLabel,
      fullAmountLabel: fullAmountLabel,
      hint: hint,
      submitLabel: submitLabel,
      emphasizePayment: emphasizePayment,
      onSubmit: onSubmit,
    ),
  );
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({
    required this.title,
    required this.customerName,
    required this.balanceLabel,
    required this.maxAmount,
    required this.amountLabel,
    required this.fullAmountLabel,
    required this.hint,
    required this.submitLabel,
    required this.emphasizePayment,
    required this.onSubmit,
  });

  final String title;
  final String customerName;
  final String balanceLabel;
  final Money maxAmount;
  final String amountLabel;
  final String fullAmountLabel;
  final String hint;
  final String submitLabel;
  final bool emphasizePayment;
  final Future<void> Function(Money amount, String note) onSubmit;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
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
    if (amount > widget.maxAmount) {
      return 'المبلغ أكبر من ${widget.balanceLabel} '
          '(${widget.maxAmount.format()})';
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
    final scheme = theme.colorScheme;
    final accent = widget.emphasizePayment ? scheme.error : scheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.customerName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.balanceLabel),
                  MoneyText(
                    widget.maxAmount,
                    fontWeight: FontWeight.bold,
                    color: accent,
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
                labelText: widget.amountLabel,
                prefixText: r'$',
                suffixIcon: TextButton(
                  onPressed: () => setState(
                    () => _amount.text = widget.maxAmount.toInputString(),
                  ),
                  child: Text(widget.fullAmountLabel),
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
              widget.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? AppStrings.loading : widget.submitLabel),
            ),
          ],
        ),
      ),
    );
  }
}
