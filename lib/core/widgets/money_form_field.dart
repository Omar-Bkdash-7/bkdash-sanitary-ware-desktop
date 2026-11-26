import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/formatting/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A text field for amounts of money (decimal keyboard, Arabic digits accepted).
class MoneyFormField extends StatelessWidget {
  const MoneyFormField({
    super.key,
    required this.controller,
    required this.label,
    this.required = true,
    this.allowZero = true,
    this.enabled = true,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final bool allowZero;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      textInputAction: textInputAction,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(r'[0-9\u0660-\u0669.,\u066B]'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixText: AppConstants.currencySymbol,
      ),
      validator: (value) =>
          Validators.money(value, required: required, allowZero: allowZero),
    );
  }
}
