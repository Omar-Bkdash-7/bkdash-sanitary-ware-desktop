import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.tryParse', () {
    test('parses whole and decimal amounts', () {
      expect(Money.tryParse('12'), const Money(1200));
      expect(Money.tryParse('12.5'), const Money(1250));
      expect(Money.tryParse('12.05'), const Money(1205));
      expect(Money.tryParse('.5'), const Money(50));
      expect(Money.tryParse('0'), Money.zero);
    });

    test('accepts a decimal comma and thousands separators', () {
      expect(Money.tryParse('12,5'), const Money(1250));
      expect(Money.tryParse('1,50'), const Money(150));
      expect(Money.tryParse('1,234.56'), const Money(123456));
      expect(Money.tryParse('1,500'), const Money(150000));
    });

    test('accepts Arabic-Indic digits and separators', () {
      expect(Money.tryParse('١٢٫٥'), const Money(1250));
      expect(Money.tryParse('١٬٢٣٤٫٥٦'), const Money(123456));
    });

    test('rejects invalid input', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('   '), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('-5'), isNull);
      expect(Money.tryParse('1.234'), isNull);
      expect(Money.tryParse('5.'), isNull);
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('1234567890123'), isNull);
    });
  });

  group('Money formatting', () {
    test('format groups thousands and keeps two decimals', () {
      expect(const Money(123456).format(), r'$1,234.56');
      expect(const Money(5).format(), r'$0.05');
      expect(const Money(100000000).format(), r'$1,000,000.00');
      expect(const Money(123456).format(withSymbol: false), '1,234.56');
    });

    test('format keeps the sign in front', () {
      expect(const Money(-250).format(), r'-$2.50');
    });

    test('toInputString is as short as possible', () {
      expect(const Money(1200).toInputString(), '12');
      expect(const Money(1250).toInputString(), '12.5');
      expect(const Money(1205).toInputString(), '12.05');
    });

    test('toPlainString always has two decimals', () {
      expect(const Money(1200).toPlainString(), '12.00');
      expect(const Money(-5).toPlainString(), '-0.05');
    });
  });

  group('Money arithmetic', () {
    test('adds, subtracts and multiplies exactly', () {
      expect(const Money(10) + const Money(20), const Money(30));
      expect(const Money(30) - const Money(50), const Money(-20));
      expect(const Money(650) * 3, const Money(1950));
      expect(-const Money(5), const Money(-5));
    });

    test('sum, min and comparisons', () {
      expect(Money.sum(const [Money(1), Money(2), Money(3)]), const Money(6));
      expect(Money.sum(const <Money>[]), Money.zero);
      expect(const Money(5).min(const Money(3)), const Money(3));
      expect(const Money(5) > const Money(3), isTrue);
      expect(const Money(5) <= const Money(3), isFalse);
      expect(const Money(5).compareTo(const Money(5)), 0);
      expect(const Money(7) == const Money(7), isTrue);
    });
  });
}
