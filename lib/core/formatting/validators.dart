import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';

/// Validators for `TextFormField.validator`; they return the error text or null.
abstract final class Validators {
  static String? requiredText(String? value) =>
      (value == null || value.trim().isEmpty) ? AppStrings.requiredField : null;

  static String? money(
    String? value, {
    bool required = true,
    bool allowZero = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? AppStrings.requiredField : null;
    }
    final amount = Money.tryParse(value);
    if (amount == null) return AppStrings.invalidAmount;
    if (!allowZero && amount.isZero) return AppStrings.amountMustBePositive;
    return null;
  }

  static String? integer(String? value, {bool required = true, int min = 0}) {
    if (value == null || value.trim().isEmpty) {
      return required ? AppStrings.requiredField : null;
    }
    final number = tryParseInt(toAsciiDigits(value));
    if (number == null || number < min) return AppStrings.invalidNumber;
    return null;
  }
}
