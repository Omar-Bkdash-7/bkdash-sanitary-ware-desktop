import 'package:bkdash_sanitary_ware/features/security/data/biometric_authenticator.dart';

/// A computer has no fingerprint sensor the app relies on: the lock screen
/// offers the PIN only.
final class NoBiometricAuthenticator implements BiometricAuthenticator {
  const NoBiometricAuthenticator();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}
