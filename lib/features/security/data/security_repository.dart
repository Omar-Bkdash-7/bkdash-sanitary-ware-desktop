import 'dart:isolate';

import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';
import 'package:bkdash_sanitary_ware/features/security/data/pin_hasher.dart';

/// Stores the PIN hash, the biometrics choice and the wrong-attempt counter.
class SecurityRepository {
  SecurityRepository(this._store);

  final KeyValueStore _store;

  static const String _hashKey = 'security.pin_hash';
  static const String _saltKey = 'security.pin_salt';
  static const String _iterationsKey = 'security.pin_iterations';
  static const String _biometricsKey = 'security.biometrics_enabled';
  static const String _failuresKey = 'security.failed_attempts';
  static const String _lockedUntilKey = 'security.locked_until_ms';

  Future<bool> hasPin() async => (await _store.getString(_hashKey)) != null;

  Future<void> savePin(String pin) async {
    final salt = PinHasher.generateSalt();
    const iterations = PinHasher.defaultIterations;
    // The hashing is CPU heavy: run it away from the UI isolate.
    final hash = await Isolate.run(
      () => PinHasher.hash(pin, salt, iterations: iterations),
    );
    await _store.setString(_saltKey, salt);
    await _store.setInt(_iterationsKey, iterations);
    await _store.setString(_hashKey, hash);
    await resetFailures();
  }

  Future<bool> verifyPin(String pin) async {
    final hash = await _store.getString(_hashKey);
    final salt = await _store.getString(_saltKey);
    if (hash == null || salt == null) return false;
    final iterations =
        await _store.getInt(_iterationsKey) ?? PinHasher.defaultIterations;
    return Isolate.run(
      () => PinHasher.verify(pin, salt, hash, iterations: iterations),
    );
  }

  Future<bool> biometricsEnabled() async =>
      (await _store.getBool(_biometricsKey)) ?? true;

  Future<void> setBiometricsEnabled({required bool enabled}) =>
      _store.setBool(_biometricsKey, enabled);

  Future<int> failedAttempts() async =>
      (await _store.getInt(_failuresKey)) ?? 0;

  Future<void> saveFailedAttempts(int count) =>
      _store.setInt(_failuresKey, count);

  /// The moment until which PIN entry is blocked (`null` when not blocked).
  Future<DateTime?> lockedUntil() async {
    final millis = await _store.getInt(_lockedUntilKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> saveLockedUntil(DateTime until) =>
      _store.setInt(_lockedUntilKey, until.millisecondsSinceEpoch);

  Future<void> resetFailures() async {
    await _store.remove(_failuresKey);
    await _store.remove(_lockedUntilKey);
  }
}
