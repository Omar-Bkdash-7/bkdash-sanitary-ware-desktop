/// Converts Arabic-Indic (U+0660-U+0669) and Persian (U+06F0-U+06F9) digits to ASCII digits so
/// numbers typed on an Arabic keyboard can be parsed.
String toAsciiDigits(String input) {
  final buffer = StringBuffer();
  for (final unit in input.runes) {
    if (unit >= 0x0660 && unit <= 0x0669) {
      buffer.writeCharCode(0x30 + unit - 0x0660);
    } else if (unit >= 0x06F0 && unit <= 0x06F9) {
      buffer.writeCharCode(0x30 + unit - 0x06F0);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Parses a whole number typed by the user; `null` when it is not one.
int? tryParseInt(String input) => int.tryParse(toAsciiDigits(input).trim());
