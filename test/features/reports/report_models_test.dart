import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 5, 14, 30);

  group('DateRange.forPeriod', () {
    test('today is a single day', () {
      final range = DateRange.forPeriod(ReportPeriod.today, today);
      expect(range.from, DateTime(2026, 11, 5));
      expect(range.to, DateTime(2026, 11, 5));
      expect(range.days, 1);
    });

    test('last 7 days includes today', () {
      final range = DateRange.forPeriod(ReportPeriod.last7Days, today);
      expect(range.fromIso, '2026-10-30');
      expect(range.toIso, '2026-11-05');
      expect(range.days, 7);
    });

    test('this month starts on the first day', () {
      final range = DateRange.forPeriod(ReportPeriod.thisMonth, today);
      expect(range.fromIso, '2026-11-01');
      expect(range.days, 5);
    });

    test('this year starts on 1 January', () {
      final range = DateRange.forPeriod(ReportPeriod.thisYear, today);
      expect(range.fromIso, '2026-01-01');
      expect(range.toIso, '2026-11-05');
    });

    test('a reversed range is invalid', () {
      expect(
        DateRange(DateTime(2026, 11, 5), DateTime(2026, 11, 1)).isValid,
        isFalse,
      );
      expect(
        DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 5)).isValid,
        isTrue,
      );
    });
  });

  group('SalesPoint.fillGaps', () {
    test('adds a zero point for every day without sales', () {
      final range = DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 4));
      final points = SalesPoint.fillGaps(range, const [
        SalesPoint(
          bucket: '2026-11-02',
          sales: Money(1000),
          profit: Money(300),
        ),
        SalesPoint(bucket: '2026-11-04', sales: Money(500), profit: Money(100)),
      ], byMonth: false);

      expect(points.map((p) => p.bucket).toList(), [
        '2026-11-01',
        '2026-11-02',
        '2026-11-03',
        '2026-11-04',
      ]);
      expect(points.map((p) => p.sales.cents).toList(), [0, 1000, 0, 500]);
    });

    test('goes across month and year ends', () {
      final range = DateRange(DateTime(2026, 12, 30), DateTime(2027, 1, 2));
      final points = SalesPoint.fillGaps(
        range,
        const <SalesPoint>[],
        byMonth: false,
      );
      expect(points.map((p) => p.bucket).toList(), [
        '2026-12-30',
        '2026-12-31',
        '2027-01-01',
        '2027-01-02',
      ]);
    });

    test('groups by month for long ranges', () {
      final range = DateRange(DateTime(2026, 11, 15), DateTime(2027, 2, 3));
      final points = SalesPoint.fillGaps(range, const [
        SalesPoint(bucket: '2027-01', sales: Money(700), profit: Money(70)),
      ], byMonth: true);
      expect(points.map((p) => p.bucket).toList(), [
        '2026-11',
        '2026-12',
        '2027-01',
        '2027-02',
      ]);
      expect(points[2].sales, const Money(700));
      expect(points[0].sales, Money.zero);
    });
  });

  group('ReportSummary.margin', () {
    test('is the profit as a percentage of the sales', () {
      const summary = ReportSummary(
        invoiceCount: 2,
        sales: Money(20000),
        profit: Money(5000),
        collected: Money(12000),
        outstanding: Money(8000),
      );
      expect(summary.margin, 25);
    });

    test('is zero when nothing was sold', () {
      expect(ReportSummary.empty.margin, 0);
    });
  });
}
