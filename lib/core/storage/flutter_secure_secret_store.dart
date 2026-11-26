import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/storage/secret_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [SecretStore] backed by the platform keystore (`flutter_secure_storage`).
///
/// The values are encrypted with a key held by Android's Keystore, so a copy of
/// the app's preferences folder does not reveal them.
///
/// The Windows implementation keeps every value in a single encrypted file and
/// serialises every access behind one shared lock. A stuck call therefore used
/// to freeze every later secret read or write (the Telegram screen would spin
/// forever). Each operation is now time-boxed and reports an Arabic error, so
/// the screen always settles into a retryable state.
final class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore([FlutterSecureStorage? storage, Duration? timeout])
    : _storage = storage ?? const FlutterSecureStorage(),
      _timeout = timeout ?? const Duration(seconds: 8);

  final FlutterSecureStorage _storage;
  final Duration _timeout;

  static const String timeoutMessage =
      'تأخّر التخزين المشفّر على هذا الجهاز ولم يستجب. أغلق البرنامج وأعد '
      'فتحه، ثم حاول مرة أخرى.';

  static const String unavailableMessage =
      'تعذّر الوصول إلى التخزين المشفّر على هذا الجهاز، فلم يُقرأ رمز البوت '
      'ولم يُحفظ. تحقّق من صلاحيات مجلد بيانات البرنامج ثم أعد المحاولة.';

  @override
  Future<String?> read(String key) => _guard(() => _storage.read(key: key));

  @override
  Future<void> write(String key, String value) =>
      _guard(() => _storage.write(key: key, value: value));

  @override
  Future<void> delete(String key) => _guard(() => _storage.delete(key: key));

  /// Runs [action] but never lets it block the screen for longer than
  /// [_timeout], and turns any storage failure into a readable message.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(
        _timeout,
        onTimeout: () => throw const SyncException(timeoutMessage),
      );
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('Secure storage failed: $error\n$stackTrace');
      throw const SyncException(unavailableMessage);
    }
  }
}
