/// A tiny encrypted store for values that must never sit in preferences:
/// the Telegram bot token and the chat id.
///
/// Only secrets go here; ordinary settings stay in the [KeyValueStore].
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}
