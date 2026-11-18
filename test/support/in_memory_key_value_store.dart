import 'package:bkdash_sanitary_ware/core/storage/key_value_store.dart';

/// A [KeyValueStore] that lives in memory, for tests.
final class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object> _values = <String, Object>{};

  /// Everything stored so far (read-only view, for assertions).
  Map<String, Object> get values => Map<String, Object>.unmodifiable(_values);

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<int?> getInt(String key) async => _values[key] as int?;

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
