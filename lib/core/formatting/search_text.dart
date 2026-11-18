import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';

/// Normalises text so Arabic searches ignore diacritics, the different forms of
/// alef and letter case: "أنبوب" matches "انبوب".
String normalizeForSearch(String input) {
  final buffer = StringBuffer();
  for (final unit in toAsciiDigits(input).toLowerCase().runes) {
    if (unit >= 0x064B && unit <= 0x0652) continue; // tashkeel
    if (unit == 0x0640) continue; // tatweel
    switch (unit) {
      case 0x0623 || 0x0625 || 0x0622: // أ إ آ
        buffer.writeCharCode(0x0627); // ا
      case 0x0649: // ى
        buffer.writeCharCode(0x064A); // ي
      case 0x0629: // ة
        buffer.writeCharCode(0x0647); // ه
      default:
        buffer.writeCharCode(unit);
    }
  }
  return buffer.toString().trim();
}
