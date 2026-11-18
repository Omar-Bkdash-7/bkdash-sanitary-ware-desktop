import 'package:bkdash_sanitary_ware/features/security/presentation/pin_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PinPad reports the digits and backspace that are tapped', (
    tester,
  ) async {
    final digits = <int>[];
    var backspaces = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PinPad(onDigit: digits.add, onBackspace: () => backspaces++),
          ),
        ),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.tap(find.text('0'));
    await tester.tap(find.text('9'));
    await tester.tap(find.byIcon(Icons.backspace_outlined));

    expect(digits, <int>[1, 0, 9]);
    expect(backspaces, 1);
    expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);
  });

  testWidgets('PinPad shows the fingerprint key only when it is allowed', (
    tester,
  ) async {
    var fingerprint = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PinPad(
              onDigit: (_) {},
              onBackspace: () {},
              onBiometric: () => fingerprint++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.fingerprint_rounded));
    expect(fingerprint, 1);
  });

  testWidgets('PinPad ignores taps while disabled', (tester) async {
    final digits = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PinPad(
              enabled: false,
              onDigit: digits.add,
              onBackspace: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('5'), warnIfMissed: false);
    expect(digits, isEmpty);
  });
}
