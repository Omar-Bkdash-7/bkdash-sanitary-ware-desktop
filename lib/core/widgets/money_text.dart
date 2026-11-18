import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:flutter/material.dart';

/// Shows an amount left-to-right so "$1,250.00" is never reordered inside
/// right-to-left Arabic text.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.color,
    this.fontWeight,
    this.withSymbol = true,
  });

  final Money amount;
  final TextStyle? style;
  final Color? color;
  final FontWeight? fontWeight;
  final bool withSymbol;

  @override
  Widget build(BuildContext context) {
    return Text(
      amount.format(withSymbol: withSymbol),
      textDirection: TextDirection.ltr,
      style: (style ?? const TextStyle()).copyWith(
        color: color,
        fontWeight: fontWeight,
      ),
    );
  }
}
