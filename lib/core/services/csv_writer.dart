/// Builds RFC 4180 CSV text that Excel opens correctly with Arabic content.
final class CsvWriter {
  final StringBuffer _buffer = StringBuffer();

  /// Appends one row. `null` becomes an empty cell; numbers are written as is.
  void writeRow(List<Object?> cells) {
    _buffer
      ..write(cells.map(_encode).join(','))
      ..write('\r\n');
  }

  /// The CSV text. The byte-order mark makes Excel detect UTF-8 (Arabic).
  String build({bool withByteOrderMark = true}) =>
      withByteOrderMark ? '\uFEFF$_buffer' : _buffer.toString();

  static String _encode(Object? cell) {
    if (cell == null) return '';
    var text = cell.toString();
    if (cell is String && _looksLikeFormula(text)) text = "'$text";
    final needsQuotes =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    if (!needsQuotes) return text;
    return '"${text.replaceAll('"', '""')}"';
  }

  /// Stops spreadsheet programs from running text such as `=1+1` as a formula.
  static bool _looksLikeFormula(String text) {
    if (text.isEmpty) return false;
    const always = <String>['=', '@', '\t', '\r'];
    if (always.contains(text[0])) return true;
    if (text[0] == '+' || text[0] == '-') {
      // "+963 ..." (phone) and "-5" (number) are fine; "+cmd|..." is not.
      return text.length > 1 && !RegExp(r'[\d\s()]').hasMatch(text[1]);
    }
    return false;
  }
}
