import 'dart:math' as math;

import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/security/data/biometric_authenticator.dart';
import 'package:bkdash_sanitary_ware/features/security/data/security_repository.dart';
import 'package:flutter/foundation.dart';

enum LockStatus { loading, needsSetup, locked, unlocked }

/// The answer to a PIN entry.
sealed class PinResult {
  const PinResult();
}

final class PinAccepted extends PinResult {
  const PinAccepted();
}

/// Wrong PIN. [attemptsLeft] is how many tries remain before entry is blocked.
final class PinRejected extends PinResult {
  const PinRejected(this.attemptsLeft);

  final int attemptsLeft;
}

/// Too many wrong tries: entry is blocked for [remaining].
final class PinBlocked extends PinResult {
  const PinBlocked(this.remaining);

  final Duration remaining;
}

/// How long PIN entry stays blocked after repeated wrong tries.
abstract final class PinLockoutPolicy {
  /// The delay after the [failures]-th wrong PIN in a row:
  /// none before [AppConstants.maxPinAttempts], then 30 s, 1 min, 2 min, ...
  /// up to 15 minutes.
  static Duration delayAfter(int failures) {
    if (failures < AppConstants.maxPinAttempts) return Duration.zero;
    final step = math.min(failures - AppConstants.maxPinAttempts, 5);
    return Duration(seconds: math.min(30 * (1 << step), 900));
  }
}

/// Owns the lock state of the app: PIN setup, unlocking, auto-lock, biometrics.
class SecurityController extends ChangeNotifier {
  SecurityController({
    required SecurityRepository repository,
    required BiometricAuthenticator biometrics,
    Clock? clock,
  }) : _repository = repository,
       _biometrics = biometrics,
       _clock = clock ?? DateTime.now;

  final SecurityRepository _repository;
  final BiometricAuthenticator _biometrics;
  final Clock _clock;

  LockStatus _status = LockStatus.loading;
  bool _biometricsAvailable = false;
  bool _biometricsEnabled = true;
  int _failures = 0;
  DateTime? _blockedUntil;
  DateTime? _pausedAt;
  bool _disposed = false;

  LockStatus get status => _status;
  bool get biometricsAvailable => _biometricsAvailable;
  bool get biometricsEnabled => _biometricsEnabled;

  /// Whether the lock screen should offer the fingerprint button.
  bool get canUseBiometrics => _biometricsAvailable && _biometricsEnabled;

  /// How long PIN entry is still blocked (`null` when it is not).
  Duration? get blockRemaining {
    final until = _blockedUntil;
    if (until == null) return null;
    final remaining = until.difference(_clock());
    return remaining.isNegative || remaining == Duration.zero
        ? null
        : remaining;
  }

  /// Reads the stored state. Call once at start-up.
  Future<void> initialize() async {
    final hasPin = await _repository.hasPin();
    _biometricsEnabled = await _repository.biometricsEnabled();
    _biometricsAvailable = await _biometrics.isAvailable();
    _failures = await _repository.failedAttempts();
    _blockedUntil = await _repository.lockedUntil();
    _status = hasPin ? LockStatus.locked : LockStatus.needsSetup;
    notifyListeners();
  }

  /// Saves the first PIN and opens the app.
  Future<void> createPin(String pin) async {
    await _repository.savePin(pin);
    _failures = 0;
    _blockedUntil = null;
    _status = LockStatus.unlocked;
    notifyListeners();
  }

  Future<PinResult> unlockWithPin(String pin) async {
    final result = await _checkPin(pin);
    if (result is PinAccepted) {
      _status = LockStatus.unlocked;
      notifyListeners();
    }
    return result;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!canUseBiometrics) return false;
    final accepted = await _biometrics.authenticate(
      reason: 'أثبت هويتك لفتح بكداش',
    );
    if (accepted) {
      await _clearFailures();
      _status = LockStatus.unlocked;
      notifyListeners();
    }
    return accepted;
  }

  void lock() {
    if (_status != LockStatus.unlocked) return;
    _status = LockStatus.locked;
    notifyListeners();
  }

  /// Changes the PIN after checking the current one.
  Future<PinResult> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final result = await _checkPin(currentPin);
    if (result is PinAccepted) await _repository.savePin(newPin);
    return result;
  }

  /// Turns fingerprint unlock on or off. Turning it on first asks for a
  /// fingerprint, so the user knows it works. Returns the resulting state.
  Future<bool> setBiometricsEnabled({required bool enabled}) async {
    if (enabled) {
      final proven = await _biometrics.authenticate(
        reason: 'تأكيد تفعيل الدخول بالبصمة',
      );
      if (!proven) return _biometricsEnabled;
    }
    await _repository.setBiometricsEnabled(enabled: enabled);
    _biometricsEnabled = enabled;
    notifyListeners();
    return enabled;
  }

  /// The app went to the background.
  void appPaused() => _pausedAt = _clock();

  /// The app came back: lock it when it stayed away too long.
  void appResumed() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null || _status != LockStatus.unlocked) return;
    if (_clock().difference(pausedAt) >= AppConstants.autoLockAfter) lock();
  }

  Future<PinResult> _checkPin(String pin) async {
    final remaining = blockRemaining;
    if (remaining != null) return PinBlocked(remaining);

    if (await _repository.verifyPin(pin)) {
      await _clearFailures();
      return const PinAccepted();
    }

    _failures++;
    await _repository.saveFailedAttempts(_failures);
    final delay = PinLockoutPolicy.delayAfter(_failures);
    if (delay > Duration.zero) {
      _blockedUntil = _clock().add(delay);
      await _repository.saveLockedUntil(_blockedUntil!);
      return PinBlocked(delay);
    }
    return PinRejected(AppConstants.maxPinAttempts - _failures);
  }

  Future<void> _clearFailures() async {
    _failures = 0;
    _blockedUntil = null;
    await _repository.resetFailures();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
