import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
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

/// A search box with a clear button.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = AppStrings.search,
  });

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (value) {
        setState(() {});
        widget.onChanged(value);
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: AppStrings.clear,
                icon: const Icon(Icons.close_rounded),
                onPressed: _clear,
              ),
      ),
    );
  }
}
