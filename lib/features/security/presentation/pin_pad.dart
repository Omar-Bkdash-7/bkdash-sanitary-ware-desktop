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

/// A numeric keypad. It is always laid out left-to-right (1 2 3 / 4 5 6 ...),
/// even though the app is right-to-left.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  /// Shows the fingerprint key when not `null`.
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in const [
              [1, 2, 3],
              [4, 5, 6],
              [7, 8, 9],
            ])
              Row(
                children: [
                  for (final digit in row)
                    _PinKey(
                      onPressed: enabled ? () => onDigit(digit) : null,
                      child: Text('$digit', style: _digitStyle),
                    ),
                ],
              ),
            Row(
              children: [
                if (onBiometric != null)
                  _PinKey(
                    onPressed: enabled ? onBiometric : null,
                    child: const Icon(Icons.fingerprint_rounded, size: 30),
                  )
                else
                  const Expanded(child: SizedBox()),
                _PinKey(
                  onPressed: enabled ? () => onDigit(0) : null,
                  child: const Text('0', style: _digitStyle),
                ),
                _PinKey(
                  onPressed: enabled ? onBackspace : null,
                  child: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const TextStyle _digitStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
  );
}

class _PinKey extends StatelessWidget {
  const _PinKey({required this.child, required this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: SizedBox(
          height: 62,
          child: FilledButton.tonal(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
