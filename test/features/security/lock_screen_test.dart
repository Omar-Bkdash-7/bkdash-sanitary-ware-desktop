import 'package:bkdash_sanitary_ware/features/security/data/biometric_authenticator.dart';
import 'package:bkdash_sanitary_ware/features/security/data/security_repository.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/lock_screen.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/in_memory_key_value_store.dart';

class _FakeBiometrics implements BiometricAuthenticator {
  bool available = true;
  bool accept = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return accept;
  }
}

/// A controller that already has the PIN "1234" and is locked.
///
/// The PIN hash is computed in an isolate, so it must be built with
/// `tester.runAsync`, outside the fake-async zone of the widget test.
Future<SecurityController> _lockedController(
  WidgetTester tester,
  _FakeBiometrics biometrics,
) async {
  final controller = await tester.runAsync(() async {
    final created = SecurityController(
      repository: SecurityRepository(InMemoryKeyValueStore()),
      biometrics: biometrics,
    );
    await created.initialize();
    await created.createPin('1234');
    created.lock();
    return created;
  });
  return controller!;
}

Widget _app(SecurityController controller) =>
    ChangeNotifierProvider<SecurityController>.value(
      value: controller,
      child: const MaterialApp(home: LockScreen()),
    );

void main() {
  testWidgets('يعرض البصمة والرمز كخيارين منفصلين قبل لوحة الأرقام', (
    tester,
  ) async {
    final biometrics = _FakeBiometrics();
    final controller = await _lockedController(tester, biometrics);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('الدخول بالبصمة'), findsOneWidget);
    expect(find.text('الدخول برمز PIN'), findsOneWidget);
    // The keypad is a separate step, not stacked with the choices.
    expect(find.text('7'), findsNothing);
    expect(biometrics.prompts, 0);
  });

  testWidgets('اختيار البصمة يطلب التحقق ويفتح التطبيق', (tester) async {
    final biometrics = _FakeBiometrics();
    final controller = await _lockedController(tester, biometrics);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الدخول بالبصمة'));
    await tester.pumpAndSettle();

    expect(biometrics.prompts, 1);
    expect(controller.status, LockStatus.unlocked);
  });

  testWidgets('اختيار الرمز يفتح لوحة الأرقام وحدها', (tester) async {
    final biometrics = _FakeBiometrics();
    final controller = await _lockedController(tester, biometrics);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الدخول برمز PIN'));
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
    expect(find.text('الدخول برمز PIN'), findsNothing);
    expect(find.text('مرحباً بعودتك'), findsNothing);

    // The fingerprint stays one tap away, without asking for it automatically.
    final fingerprintButton = find.text('الدخول بالبصمة');
    await tester.ensureVisible(fingerprintButton);
    await tester.pumpAndSettle();
    await tester.tap(fingerprintButton);
    await tester.pumpAndSettle();
    expect(find.text('مرحباً بعودتك'), findsOneWidget);
    expect(biometrics.prompts, 0);
  });

  testWidgets('بلا بصمة مسجّلة تُعرض لوحة الأرقام مباشرة', (tester) async {
    final biometrics = _FakeBiometrics()..available = false;
    final controller = await _lockedController(tester, biometrics);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
    expect(find.text('الدخول بالبصمة'), findsNothing);
  });
}
