/// Typed access to the untyped rows returned by sqflite.
extension RowReader on Map<String, Object?> {
  int readInt(String column) => (this[column] as num?)?.toInt() ?? 0;

  int? readIntOrNull(String column) => (this[column] as num?)?.toInt();

  String readString(String column) => (this[column] as String?) ?? '';
}
