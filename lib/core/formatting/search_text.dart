import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';

/// Normalises text so Arabic searches ignore diacritics, the different forms of
/// alef variants and letter case, so either alef spelling matches.
String normalizeForSearch(String input) {
  final buffer = StringBuffer();
  for (final unit in toAsciiDigits(input).toLowerCase().runes) {
    if (unit >= 0x064B && unit <= 0x0652) continue; // tashkeel
    if (unit == 0x0640) continue; // tatweel
    switch (unit) {
      case 0x0623 || 0x0625 || 0x0622: // alef variants: U+0623, U+0625, U+0622
        buffer.writeCharCode(0x0627); // to bare alef U+0627
      case 0x0649: // alef maqsura U+0649
        buffer.writeCharCode(0x064A); // to yeh U+064A
      case 0x0629: // teh marbuta U+0629
        buffer.writeCharCode(0x0647); // to heh U+0647
      default:
        buffer.writeCharCode(unit);
    }
  }
  return buffer.toString().trim();
}
