import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Asks for the current PIN and a new one. Closes with `true` when changed.
class ChangePinDialog extends StatefulWidget {
  const ChangePinDialog({super.key});

  @override
  State<ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<ChangePinDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _pinRule(String? value) {
    if (value == null || value.length != AppConstants.pinLength) {
      return 'أدخل ${AppConstants.pinLength} أرقام';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final security = context.read<SecurityController>();
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await security.changePin(
      currentPin: _current.text,
      newPin: _new.text,
    );
    if (!mounted) return;
    switch (result) {
      case PinAccepted():
        navigator.pop(true);
      case PinRejected(:final attemptsLeft):
        setState(() {
          _saving = false;
          _error = 'رمز PIN الحالي غير صحيح. المحاولات المتبقية: $attemptsLeft';
        });
      case PinBlocked():
        setState(() {
          _saving = false;
          _error = 'تم إيقاف الإدخال مؤقتاً بسبب المحاولات الخاطئة.';
        });
    }
  }

  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, counterText: '');

  @override
  Widget build(BuildContext context) {
    final formatters = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: const Text('تغيير رمز PIN'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: AppConstants.pinLength,
                inputFormatters: formatters,
                decoration: _decoration('الرمز الحالي'),
                validator: _pinRule,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _new,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: AppConstants.pinLength,
                inputFormatters: formatters,
                decoration: _decoration('الرمز الجديد'),
                validator: _pinRule,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: AppConstants.pinLength,
                inputFormatters: formatters,
                decoration: _decoration('تأكيد الرمز الجديد'),
                validator: (value) => value != _new.text
                    ? 'الرمزان غير متطابقين'
                    : _pinRule(value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text(AppStrings.save),
        ),
      ],
    );
  }
}
