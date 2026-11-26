import 'package:bkdash_sanitary_ware/core/formatting/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A text field for whole numbers such as quantities.
class IntegerFormField extends StatelessWidget {
  const IntegerFormField({
    super.key,
    required this.controller,
    required this.label,
    this.required = true,
    this.min = 0,
    this.enabled = true,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final int min;
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
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9\u0660-\u0669]')),
      ],
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          Validators.integer(value, required: required, min: min),
    );
  }
}
