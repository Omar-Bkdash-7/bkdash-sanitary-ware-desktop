import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:flutter/material.dart';

/// The row of dots that shows how many PIN digits were typed.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, this.hasError = false});

  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hasError ? scheme.error : scheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < AppConstants.pinLength; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? color : Colors.transparent,
              border: Border.all(color: color, width: 2),
            ),
          ),
      ],
    );
  }
}
