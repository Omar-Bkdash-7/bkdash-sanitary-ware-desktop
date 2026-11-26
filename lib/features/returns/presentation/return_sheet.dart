import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_form_field.dart';
import 'package:bkdash_sanitary_ware/core/widgets/money_text.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/returns/data/return_repository.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Takes pieces back from the customer and closes with `true` when saved.
///
/// The quantities are limited to what is still returnable on each line, and the
/// prices come from the invoice itself: the credit is exactly what the customer
/// was charged for those pieces, whatever the catalogue says today.
Future<bool?> showReturnSheet(
  BuildContext context, {
  required Invoice invoice,
  required ReturnRepository repository,
}) {
  return showFormSheet<bool>(
    context,
    builder: (_) => _ReturnForm(invoice: invoice, repository: repository),
  );
}

class _ReturnForm extends StatefulWidget {
  const _ReturnForm({required this.invoice, required this.repository});

  final Invoice invoice;
  final ReturnRepository repository;

  @override
  State<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends State<_ReturnForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _refund = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final Map<int, TextEditingController> _quantities =
      <int, TextEditingController>{};

  List<ReturnableLine> _lines = const <ReturnableLine>[];
  Money _refunded = Money.zero;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _refund.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lines = await widget.repository.returnableLines(widget.invoice.id);
      final refunded = await widget.repository.refundedForInvoice(
        widget.invoice.id,
      );
      if (!mounted) return;
      setState(() {
        _lines = lines.where((line) => line.canReturn).toList();
        for (final line in _lines) {
          _quantities[line.invoiceItemId] = TextEditingController(text: '0');
        }
        _refunded = refunded;
        _loading = false;
      });
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  int _quantityOf(ReturnableLine line) =>
      (tryParseInt(_quantities[line.invoiceItemId]!.text) ?? 0).clamp(
        0,
        line.remaining,
      );

  List<ReturnLine> get _chosen => <ReturnLine>[
    for (final line in _lines)
      if (_quantityOf(line) > 0)
        ReturnLine.fromReturnable(line, quantity: _quantityOf(line)),
  ];

  Money get _credit => Money.sum(_chosen.map((line) => line.lineTotal));

  /// What the customer paid on this invoice and did not take back yet.
  Money get _refundable {
    final left = widget.invoice.paid - _refunded;
    return left.isPositive ? left : Money.zero;
  }

  Money get _refundLimit => _refundable < _credit ? _refundable : _credit;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final chosen = _chosen;
    if (chosen.isEmpty) {
      setState(() => _error = 'اختر كمية واحدة على الأقل لإرجاعها.');
      return;
    }
    final refund = Money.tryParse(_refund.text) ?? Money.zero;
    if (refund > _refundLimit) {
      setState(
        () => _error =
            'المبلغ المعاد للزبون أكبر من المسموح (${_refundLimit.format()}).',
      );
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.create(
        ReturnDraft(
          invoiceId: widget.invoice.id,
          lines: chosen,
          refund: refund,
          notes: _notes.text,
        ),
      );
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إرجاع أصناف من الفاتورة #${widget.invoice.id}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              widget.invoice.customerName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_lines.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'كل كميات هذه الفاتورة أُرجعت بالفعل، فلا شيء يمكن إرجاعه.',
                ),
              )
            else ...[
              for (final line in _lines) ...[
                _ReturnableTile(
                  line: line,
                  controller: _quantities[line.invoiceItemId]!,
                  onChanged: () => setState(() => _error = null),
                ),
                const SizedBox(height: 8),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('قيمة المرتجع بسعر البيع'),
                        MoneyText(
                          _credit,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تُخصم من دين الزبون على هذه الفاتورة، وتعود القطع إلى '
                      'المخزون في حاويتها.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MoneyFormField(
                controller: _refund,
                label: 'نقد يُعاد للزبون الآن',
                required: false,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 4),
              Text(
                'المدفوع على هذه الفاتورة ${widget.invoice.paid.format()}، '
                'والمتاح لإعادته نقداً ${_refundLimit.format()}. '
                'ما لا يُعاد نقداً يُخصم من الدين.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'سبب الإرجاع (اختياري)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || _chosen.isEmpty ? null : _save,
                child: Text(_saving ? 'جارٍ الحفظ…' : 'تسجيل المرتجع'),
              ),
            ],
            if (_error != null && _lines.isEmpty) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One invoice line with the quantity that comes back.
class _ReturnableTile extends StatelessWidget {
  const _ReturnableTile({
    required this.line,
    required this.controller,
    required this.onChanged,
  });

  final ReturnableLine line;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = line.line.container > 0
        ? '${line.line.itemName}  •  حاوية ${line.line.container}'
        : line.line.itemName;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  '${line.line.quantity} ${line.line.unit} × ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                MoneyText(
                  line.line.unitPrice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '  •  متبقٍ للإرجاع: ${line.remaining}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9\u0660-\u0669]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'الكمية المرتجعة',
                      isDense: true,
                    ),
                    validator: (value) {
                      final quantity = tryParseInt(value ?? '') ?? 0;
                      if (quantity < 0 || quantity > line.remaining) {
                        return 'من 0 إلى ${line.remaining}';
                      }
                      return null;
                    },
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    controller.text = '${line.remaining}';
                    onChanged();
                  },
                  child: const Text('الكل'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
