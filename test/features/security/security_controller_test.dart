import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/features/security/data/biometric_authenticator.dart';
import 'package:bkdash_sanitary_ware/features/security/data/security_repository.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late InMemoryKeyValueStore store;
  late _FakeBiometrics biometrics;
  late DateTime now;

  SecurityController newController() => SecurityController(
    repository: SecurityRepository(store),
    biometrics: biometrics,
    clock: () => now,
  );

  /// A controller whose PIN is "1234" and which is currently locked.
  Future<SecurityController> lockedController() async {
    final first = newController();
    await first.initialize();
    await first.createPin('1234');
    first.dispose();
    final controller = newController();
    await controller.initialize();
    return controller;
  }

  setUp(() {
    store = InMemoryKeyValueStore();
    biometrics = _FakeBiometrics();
    now = DateTime(2026, 11, 2, 10);
  });

  group('lock policy', () {
    test('no delay before the allowed number of wrong tries', () {
      expect(PinLockoutPolicy.delayAfter(0), Duration.zero);
      expect(
        PinLockoutPolicy.delayAfter(AppConstants.maxPinAttempts - 1),
        Duration.zero,
      );
    });

    test('the delay doubles and is capped at 15 minutes', () {
      expect(PinLockoutPolicy.delayAfter(5), const Duration(seconds: 30));
      expect(PinLockoutPolicy.delayAfter(6), const Duration(seconds: 60));
      expect(PinLockoutPolicy.delayAfter(7), const Duration(seconds: 120));
      expect(PinLockoutPolicy.delayAfter(30), const Duration(minutes: 15));
    });
  });

  group('first run and unlocking', () {
    test('without a PIN the app asks to create one, then opens', () async {
      final controller = newController();
      expect(controller.status, LockStatus.loading);

      await controller.initialize();
      expect(controller.status, LockStatus.needsSetup);

      await controller.createPin('1234');
      expect(controller.status, LockStatus.unlocked);
    });

    test('the PIN itself is never stored, only a salted hash', () async {
      final controller = newController();
      await controller.initialize();
      await controller.createPin('4821');

      expect(store.values.values.contains('4821'), isFalse);
      expect(store.values['security.pin_hash'], isA<String>());
      expect(store.values['security.pin_salt'], isA<String>());
      expect(store.values['security.pin_hash'] == '4821', isFalse);
    });

    test('the right PIN unlocks, a wrong one counts attempts', () async {
      final controller = await lockedController();
      expect(controller.status, LockStatus.locked);

      final wrong = await controller.unlockWithPin('0000');
      expect(
        wrong,
        isA<PinRejected>().having((r) => r.attemptsLeft, 'attemptsLeft', 4),
      );
      expect(controller.status, LockStatus.locked);

      expect(await controller.unlockWithPin('1234'), isA<PinAccepted>());
      expect(controller.status, LockStatus.unlocked);
    });

    test('five wrong PINs block entry, even for the right PIN', () async {
      final controller = await lockedController();
      for (var i = 0; i < 4; i++) {
        expect(await controller.unlockWithPin('0000'), isA<PinRejected>());
      }
      final fifth = await controller.unlockWithPin('0000');
      expect(
        fifth,
        isA<PinBlocked>().having(
          (b) => b.remaining,
          'remaining',
          const Duration(seconds: 30),
        ),
      );
      expect(controller.blockRemaining, isNotNull);
      expect(await controller.unlockWithPin('1234'), isA<PinBlocked>());
      expect(controller.status, LockStatus.locked);

      now = now.add(const Duration(seconds: 31));
      expect(controller.blockRemaining, isNull);
      expect(await controller.unlockWithPin('1234'), isA<PinAccepted>());
    });

    test('the block survives restarting the app', () async {
      final controller = await lockedController();
      for (var i = 0; i < 5; i++) {
        await controller.unlockWithPin('0000');
      }
      controller.dispose();

      final restarted = newController();
      await restarted.initialize();
      expect(restarted.blockRemaining, isNotNull);
      expect(await restarted.unlockWithPin('1234'), isA<PinBlocked>());
    });

    test('a correct PIN forgets the earlier wrong tries', () async {
      final controller = await lockedController();
      await controller.unlockWithPin('0000');
      await controller.unlockWithPin('0000');
      await controller.unlockWithPin('1234');
      controller.lock();

      final wrong = await controller.unlockWithPin('0000');
      expect(
        wrong,
        isA<PinRejected>().having((r) => r.attemptsLeft, 'attemptsLeft', 4),
      );
    });
  });

  group('biometrics', () {
    test('unlocks with a fingerprint when available and enabled', () async {
      final controller = await lockedController();
      expect(controller.canUseBiometrics, isTrue);
      expect(await controller.unlockWithBiometrics(), isTrue);
      expect(controller.status, LockStatus.unlocked);
    });

    test('a refused fingerprint keeps the app locked', () async {
      final controller = await lockedController();
      biometrics.accept = false;
      expect(await controller.unlockWithBiometrics(), isFalse);
      expect(controller.status, LockStatus.locked);
    });

    test('is not offered when the device has no fingerprint', () async {
      biometrics.available = false;
      final controller = await lockedController();
      expect(controller.canUseBiometrics, isFalse);
      expect(await controller.unlockWithBiometrics(), isFalse);
      expect(biometrics.prompts, 0);
    });

    test(
      'turning it off is remembered; turning it on needs a fingerprint',
      () async {
        final controller = await lockedController();
        expect(await controller.setBiometricsEnabled(enabled: false), isFalse);
        expect(controller.canUseBiometrics, isFalse);

        biometrics.accept = false;
        expect(await controller.setBiometricsEnabled(enabled: true), isFalse);

        biometrics.accept = true;
        expect(await controller.setBiometricsEnabled(enabled: true), isTrue);

        final restarted = newController();
        await restarted.initialize();
        expect(restarted.biometricsEnabled, isTrue);
      },
    );
  });

  group('auto lock', () {
    test('locks after a long time in the background', () async {
      final controller = await lockedController();
      await controller.unlockWithPin('1234');

      controller.appPaused();
      now = now.add(AppConstants.autoLockAfter);
      controller.appResumed();
      expect(controller.status, LockStatus.locked);
    });

    test('stays open after a short pause', () async {
      final controller = await lockedController();
      await controller.unlockWithPin('1234');

      controller.appPaused();
      now = now.add(const Duration(seconds: 5));
      controller.appResumed();
      expect(controller.status, LockStatus.unlocked);
    });
  });

  group('changing the PIN', () {
    test('needs the current PIN', () async {
      final controller = await lockedController();
      final result = await controller.changePin(
        currentPin: '9999',
        newPin: '5555',
      );
      expect(result, isA<PinRejected>());

      expect(await controller.unlockWithPin('1234'), isA<PinAccepted>());
    });

    test('the new PIN replaces the old one', () async {
      final controller = await lockedController();
      final result = await controller.changePin(
        currentPin: '1234',
        newPin: '5555',
      );
      expect(result, isA<PinAccepted>());

      controller.lock();
      expect(await controller.unlockWithPin('1234'), isA<PinRejected>());
      expect(await controller.unlockWithPin('5555'), isA<PinAccepted>());
    });
  });
}
