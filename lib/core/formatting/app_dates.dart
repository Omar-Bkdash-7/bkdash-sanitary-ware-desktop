/// Date helpers. Dates are stored as ISO-8601 text and displayed with Western
/// digits and Levantine (Syrian) month names.
abstract final class AppDates {
  static const List<String> _weekdays = <String>[
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static const List<String> months = <String>[
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// "2026-11-02" - the form used in the database.
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

  /// "2026-11-02T15:30:05" (local time, no zone) - the form used in the database.
  static String isoDateTime(DateTime date) =>
      '${isoDate(date)}T${_two(date.hour)}:${_two(date.minute)}:${_two(date.second)}';

  /// Parses "2026-11-02" (also a full ISO date-time); `null` when malformed.
  static DateTime? tryParse(String text) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(text);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.tryParse(match.group(4) ?? '') ?? 0,
      int.tryParse(match.group(5) ?? '') ?? 0,
      int.tryParse(match.group(6) ?? '') ?? 0,
    );
  }

  /// "2026/11/02"
  static String display(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}/${_two(date.month)}/${_two(date.day)}';

  /// Same as [display] but starting from the database text.
  static String displayIso(String iso) {
    final parsed = tryParse(iso);
    return parsed == null ? iso : display(parsed);
  }

  /// "03:30 م"
  static String time12(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '${_two(hour)}:${_two(date.minute)} ${date.hour < 12 ? 'ص' : 'م'}';
  }

  /// Same as [time12] but starting from the database text.
  static String timeIso(String iso) {
    final parsed = tryParse(iso);
    return parsed == null ? '' : time12(parsed);
  }

  /// "الاثنين"
  static String weekday(DateTime date) => _weekdays[date.weekday - 1];

  /// "تشرين الثاني 2026"
  static String monthYear(DateTime date) =>
      '${months[date.month - 1]} ${date.year}';

  /// "2026/11/02 - الاثنين"
  static String displayWithWeekday(DateTime date) =>
      '${display(date)} - ${weekday(date)}';

  /// "15:30" - the clock part of a file name (`bkdash_2026-11-02_15:30.db`).
  static String fileClock(DateTime date) =>
      '${_two(date.hour)}:${_two(date.minute)}';

  /// "20261102_153005" - used in file names.
  static String fileStamp(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}${_two(date.month)}${_two(date.day)}'
      '_${_two(date.hour)}${_two(date.minute)}${_two(date.second)}';

  /// The date at 00:00 (drops the time of day).
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
