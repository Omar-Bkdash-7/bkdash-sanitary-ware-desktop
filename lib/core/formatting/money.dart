import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';

/// An amount of money kept as a whole number of cents (1/100 of a dollar).
///
/// Integers avoid the rounding drift of `double`: 0.1 + 0.2 is exactly 0.30.
final class Money implements Comparable<Money> {
  const Money(this.cents);

  static const Money zero = Money(0);

  final int cents;

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator *(int factor) => Money(cents * factor);
  Money operator -() => Money(-cents);
  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  /// The smaller of the two amounts.
  Money min(Money other) => cents <= other.cents ? this : other;

  /// Sums [amounts]; an empty list gives [zero].
  static Money sum(Iterable<Money> amounts) =>
      amounts.fold(zero, (total, amount) => total + amount);

  /// Parses text typed by a user ("12", "12.5", "12,50", "1,234.56", "١٢٫٥").
  ///
  /// Returns `null` for empty, negative, malformed text or more than two
  /// decimal places.
  static Money? tryParse(String input) {
    var text = toAsciiDigits(input).replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
    text = text.replaceAll('\u066C', ',').replaceAll('\u066B', '.');
    if (text.isEmpty) return null;

    if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d{1,2})?$').hasMatch(text)) {
      text = text.replaceAll(',', ''); // "1,234.50" -> "1234.50"
    } else if (RegExp(r'^\d*,\d{1,2}$').hasMatch(text)) {
      text = text.replaceAll(',', '.'); // "12,5" -> "12.5"
    }

    final match = RegExp(r'^(\d*)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) return null;
    final wholeText = match.group(1)!;
    final fractionText = match.group(2) ?? '';
    if (wholeText.isEmpty && fractionText.isEmpty) return null;
    if (wholeText.length > 12) return null;

    final whole = wholeText.isEmpty ? 0 : int.parse(wholeText);
    final fraction = fractionText.isEmpty
        ? 0
        : int.parse(fractionText.padRight(2, '0'));
    return Money(whole * 100 + fraction);
  }

  /// "$1,234.50" (or "1,234.50" without the symbol).
  String format({bool withSymbol = true}) {
    final absolute = cents.abs();
    final whole = _group((absolute ~/ 100).toString());
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    final body = '$whole.$fraction';
    final text = withSymbol ? '${AppConstants.currencySymbol}$body' : body;
    return isNegative ? '-$text' : text;
  }

  /// A plain value suitable for a text field ("12" or "12.5" or "12.05").
  String toInputString() {
    final absolute = cents.abs();
    final whole = absolute ~/ 100;
    final fraction = absolute % 100;
    final sign = isNegative ? '-' : '';
    if (fraction == 0) return '$sign$whole';
    final padded = fraction.toString().padLeft(2, '0');
    final trimmed = padded.endsWith('0') ? padded.substring(0, 1) : padded;
    return '$sign$whole.$trimmed';
  }

  /// The amount as a decimal number with two places ("1234.50") for CSV files.
  String toPlainString() {
    final absolute = cents.abs();
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    return '${isNegative ? '-' : ''}${absolute ~/ 100}.$fraction';
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money($cents)';

  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
