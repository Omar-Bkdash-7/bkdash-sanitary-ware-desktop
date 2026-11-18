import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/ascii_digits.dart';
import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDates', () {
    final date = DateTime(2026, 11, 2, 15, 30, 5);

    test('isoDate and isoDateTime use the database format', () {
      expect(AppDates.isoDate(date), '2026-11-02');
      expect(AppDates.isoDateTime(date), '2026-11-02T15:30:05');
    });

    test('tryParse reads dates with or without a time', () {
      expect(AppDates.tryParse('2026-11-02'), DateTime(2026, 11, 2));
      expect(AppDates.tryParse('2026-11-02T15:30:05'), date);
      expect(AppDates.tryParse('not a date'), isNull);
    });

    test('display helpers use Western digits', () {
      expect(AppDates.display(date), '2026/11/02');
      expect(AppDates.displayIso('2026-11-02T15:30:05'), '2026/11/02');
      expect(AppDates.time12(date), '03:30 م');
      expect(AppDates.time12(DateTime(2026, 1, 1, 0, 5)), '12:05 ص');
      expect(AppDates.timeIso('2026-11-02T09:07:00'), '09:07 ص');
      expect(AppDates.weekday(date), 'الاثنين');
      expect(AppDates.monthYear(date), 'تشرين الثاني 2026');
      expect(AppDates.fileStamp(date), '20261102_153005');
      expect(AppDates.fileClock(date), '15-30');
      expect(AppDates.fileClock(DateTime(2026, 1, 5, 9, 7)), '09-07');
    });

    test('dateOnly drops the time of day', () {
      expect(AppDates.dateOnly(date), DateTime(2026, 11, 2));
    });
  });

  group('digits', () {
    test('Arabic-Indic and Persian digits become ASCII', () {
      expect(toAsciiDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(toAsciiDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(toAsciiDigits('12 abc'), '12 abc');
    });

    test('tryParseInt', () {
      expect(tryParseInt(' ١٢ '), 12);
      expect(tryParseInt('1.5'), isNull);
      expect(tryParseInt(''), isNull);
    });
  });

  group('normalizeForSearch', () {
    test('ignores alef forms, diacritics and case', () {
      expect(normalizeForSearch('أنبوب'), normalizeForSearch('انبوب'));
      expect(normalizeForSearch('إبريق'), normalizeForSearch('ابريق'));
      expect(normalizeForSearch('حَنَفِيَّة'), normalizeForSearch('حنفيه'));
      expect(normalizeForSearch('VAL-01'), 'val-01');
    });

    test('digits are normalised too', () {
      expect(normalizeForSearch('١٢'), '12');
    });

    test('a search text is found inside a longer name', () {
      expect(
        normalizeForSearch(
          'سكر دحلة كلة حديد',
        ).contains(normalizeForSearch('دحله')),
        isTrue,
      );
    });
  });
}
