import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:bkdash_sanitary_ware/features/purchases/models/purchase.dart';

/// The ready-made periods of the reports screen.
enum ReportPeriod {
  today('اليوم'),
  last7Days('آخر 7 أيام'),
  thisMonth('هذا الشهر'),
  thisYear('هذه السنة'),
  custom('فترة مخصصة');

  const ReportPeriod(this.label);

  final String label;
}

/// An inclusive range of days (the time of day is ignored).
final class DateRange {
  DateRange(DateTime from, DateTime to)
    : from = AppDates.dateOnly(from),
      to = AppDates.dateOnly(to);

  /// The range of a ready-made [period] as seen from [today].
  factory DateRange.forPeriod(ReportPeriod period, DateTime today) {
    final day = AppDates.dateOnly(today);
    switch (period) {
      case ReportPeriod.today:
        return DateRange(day, day);
      case ReportPeriod.last7Days:
        return DateRange(day.subtract(const Duration(days: 6)), day);
      case ReportPeriod.thisMonth:
        return DateRange(DateTime(day.year, day.month, 1), day);
      case ReportPeriod.thisYear:
        return DateRange(DateTime(day.year, 1, 1), day);
      case ReportPeriod.custom:
        return DateRange(day, day);
    }
  }

  final DateTime from;
  final DateTime to;

  String get fromIso => AppDates.isoDate(from);
  String get toIso => AppDates.isoDate(to);

  int get days => to.difference(from).inDays + 1;

  bool get isValid => !to.isBefore(from);
}

/// Headline numbers of a period.
final class ReportSummary {
  const ReportSummary({
    required this.invoiceCount,
    required this.sales,
    required this.profit,
    required this.collected,
    required this.outstanding,
    required this.purchaseCount,
    required this.purchases,
    required this.paidToCustomers,
    required this.payables,
  });

  static const ReportSummary empty = ReportSummary(
    invoiceCount: 0,
    sales: Money.zero,
    profit: Money.zero,
    collected: Money.zero,
    outstanding: Money.zero,
    purchaseCount: 0,
    purchases: Money.zero,
    paidToCustomers: Money.zero,
    payables: Money.zero,
  );

  final int invoiceCount;

  /// Total of the invoices issued in the period.
  final Money sales;

  /// Profit of those invoices.
  final Money profit;

  /// Cash received in the period (including old debts paid in it).
  final Money collected;

  /// What is still unpaid on the invoices issued in the period.
  final Money outstanding;

  /// Purchases made from customers in the period.
  final int purchaseCount;

  /// Total of those purchases (what the shop owes for the pieces).
  final Money purchases;

  /// Cash paid to customers in the period (including old purchases).
  final Money paidToCustomers;

  /// What is still unpaid on the purchases made in the period.
  final Money payables;

  /// Cash actually kept in the period: received minus paid to customers.
  Money get netCash => collected - paidToCustomers;

  /// Profit as a percentage of sales (0 when there are no sales).
  double get margin => sales.isPositive ? profit.cents * 100 / sales.cents : 0;
}

/// Sales of one day or one month (a point of the chart).
final class SalesPoint {
  const SalesPoint({
    required this.bucket,
    required this.sales,
    required this.profit,
  });

  /// "2026-11-02" for a day or "2026-11" for a month.
  final String bucket;
  final Money sales;
  final Money profit;

  /// One point for every day (or month) of [range]: days without sales get a
  /// point of zero, so the chart axis is continuous.
  static List<SalesPoint> fillGaps(
    DateRange range,
    List<SalesPoint> points, {
    required bool byMonth,
  }) {
    final known = <String, SalesPoint>{
      for (final point in points) point.bucket: point,
    };
    final result = <SalesPoint>[];

    SalesPoint pointFor(String key) =>
        known[key] ??
        SalesPoint(bucket: key, sales: Money.zero, profit: Money.zero);

    if (byMonth) {
      var cursor = DateTime(range.from.year, range.from.month);
      final last = DateTime(range.to.year, range.to.month);
      while (!cursor.isAfter(last)) {
        result.add(pointFor(AppDates.isoDate(cursor).substring(0, 7)));
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
    } else {
      var cursor = range.from;
      while (!cursor.isAfter(range.to)) {
        result.add(pointFor(AppDates.isoDate(cursor)));
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      }
    }
    return result;
  }
}

final class CategorySales {
  const CategorySales({
    required this.category,
    required this.sales,
    required this.profit,
    required this.pieces,
  });

  final String category;
  final Money sales;
  final Money profit;
  final int pieces;
}

final class TopItem {
  const TopItem({
    required this.name,
    required this.pieces,
    required this.sales,
  });

  final String name;
  final int pieces;
  final Money sales;
}

/// Everything the reports screen shows for one [range].
final class ReportData {
  const ReportData({
    required this.range,
    required this.summary,
    required this.series,
    required this.groupedByMonth,
    required this.categories,
    required this.topItems,
    required this.invoices,
    required this.purchases,
  });

  final DateRange range;
  final ReportSummary summary;
  final List<SalesPoint> series;

  /// `true` when [series] has one point per month instead of per day.
  final bool groupedByMonth;
  final List<CategorySales> categories;
  final List<TopItem> topItems;
  final List<Invoice> invoices;
  final List<Purchase> purchases;
}
