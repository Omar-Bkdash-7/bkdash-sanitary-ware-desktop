import 'package:bkdash_sanitary_ware/core/storage/secret_store.dart';

/// A [SecretStore] that lives in memory, for tests.
final class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  /// Everything stored so far (read-only view, for assertions).
  Map<String, String> get values => Map<String, String>.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
