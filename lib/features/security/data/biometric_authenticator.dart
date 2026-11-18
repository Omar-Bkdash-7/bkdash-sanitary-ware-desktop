/// Fingerprint / face unlock, behind an interface so it can be faked in tests.
abstract interface class BiometricAuthenticator {
  /// Whether the device can do biometric authentication right now
  /// (hardware present and at least one fingerprint / face enrolled).
  Future<bool> isAvailable();

  /// Asks the user to authenticate; `false` when cancelled or not recognised.
  Future<bool> authenticate({required String reason});
}
