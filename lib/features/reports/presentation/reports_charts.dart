import 'dart:math' as math;

import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

String _compact(double dollars) {
  final value = dollars.abs();
  if (value >= 1000000) return '${(dollars / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(dollars / 1000).toStringAsFixed(1)}k';
  return dollars.toStringAsFixed(0);
}

/// Sales and profit per day (or per month for long periods).
///
/// Charts are drawn left-to-right so time always runs the same way; the chart
/// scrolls sideways when there are many bars.
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.series, required this.byMonth});

  final List<SalesPoint> series;
  final bool byMonth;

  static const double _barSlot = 30;

  String _label(String bucket) {
    if (byMonth) {
      final parts = bucket.split('-');
      return '${int.parse(parts[1])}/${parts[0].substring(2)}';
    }
    return '${int.parse(bucket.substring(8))}';
  }

  String _fullLabel(String bucket) {
    if (byMonth) return bucket;
    return bucket.replaceAll('-', '/');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = series.fold<double>(
      0,
      (maxSoFar, point) => math.max(maxSoFar, point.sales.cents / 100),
    );
    final top = maxValue <= 0 ? 10.0 : maxValue * 1.2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(constraints.maxWidth, series.length * _barSlot);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: width,
              height: 230,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 8),
                child: BarChart(
                  BarChartData(
                    maxY: top,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(
                              _compact(value),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 26,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= series.length) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                _label(series[index].bucket),
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final point = series[groupIndex];
                          return BarTooltipItem(
                            '${_fullLabel(point.bucket)}\n'
                            '${point.sales.format()}  /  ${point.profit.format()}',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          );
                        },
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < series.length; i++)
                        BarChartGroupData(
                          x: i,
                          barsSpace: 2,
                          barRods: [
                            BarChartRodData(
                              toY: series[i].sales.cents / 100,
                              width: 9,
                              color: scheme.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                            BarChartRodData(
                              toY: math.max(series[i].profit.cents / 100, 0),
                              width: 9,
                              color: scheme.success,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The colours of the category slices (repeated when there are more).
const List<Color> kCategoryColors = <Color>[
  Color(0xFF0D9488),
  Color(0xFF0284C7),
  Color(0xFFD97706),
  Color(0xFF7C3AED),
  Color(0xFFE11D48),
  Color(0xFF65A30D),
  Color(0xFF64748B),
];

/// Share of each category in the sales, as a donut chart with a legend.
class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({super.key, required this.categories});

  final List<CategorySales> categories;

  /// The biggest categories are listed; the rest are merged into an "Other" slice.
  static const int _maxSlices = 6;

  List<CategorySales> get _slices {
    if (categories.length <= _maxSlices) return categories;
    final head = categories.take(_maxSlices - 1).toList();
    final rest = categories.skip(_maxSlices - 1);
    return [
      ...head,
      CategorySales(
        category: 'أخرى',
        sales: Money.sum(rest.map((c) => c.sales)),
        profit: Money.sum(rest.map((c) => c.profit)),
        pieces: rest.fold(0, (sum, c) => sum + c.pieces),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slices = _slices;
    final total = Money.sum(slices.map((slice) => slice.sales));
    double percent(CategorySales slice) =>
        total.isPositive ? slice.sales.cents * 100 / total.cents : 0;

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 38,
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    PieChartSectionData(
                      value: math.max(slices[i].sales.cents / 100, 0.01),
                      color: kCategoryColors[i % kCategoryColors.length],
                      radius: 56,
                      title: percent(slices[i]) >= 6
                          ? '${percent(slices[i]).toStringAsFixed(0)}%'
                          : '',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: kCategoryColors[i % kCategoryColors.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(slices[i].category)),
                Text(
                  '${percent(slices[i]).toStringAsFixed(1)}%  ',
                  style: theme.textTheme.bodySmall,
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  slices[i].sales.format(),
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
